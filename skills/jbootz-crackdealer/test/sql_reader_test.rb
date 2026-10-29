require_relative 'test_helper'
require 'time'

class SqlReaderTest < CrackdealerTest
  FIXED_TIME = Time.iso8601('2026-10-23T12:00:00Z').freeze

  def setup
    super
    assert_equal 'constant', defined?(Crackdealer::SqlReader), 'SQL reader implementation is not loaded yet'
    @database = build_database
    @database.initialize!
    Crackdealer::Importer.new(database: @database, clock: -> { FIXED_TIME })
      .import(path: fixture_path('library.xml'))
    seed_recommendation
    @sql_reader = Crackdealer::SqlReader.new(database: @database)
  end

  def test_allows_joins_across_library_and_history
    result = @sql_reader.query(
      sql: "SELECT tracks.source_track_id, recommendations.title FROM tracks JOIN recommendations ON recommendations.artist = tracks.artist WHERE tracks.source_track_id = 1"
    )

    assert_equal ['source_track_id', 'title'], result.fetch(:columns)
    assert_equal [[1, 'History Song']], result.fetch(:rows)
  end

  def test_allows_common_table_expressions
    result = @sql_reader.query(sql: <<~SQL)
      WITH track_rows AS (
        SELECT source_track_id FROM tracks WHERE source_track_id <= 3
      )
      SELECT source_track_id FROM track_rows ORDER BY source_track_id
    SQL

    assert_equal [[1], [2], [3]], result.fetch(:rows)
  end

  def test_allows_bounded_recursive_common_table_expressions
    result = @sql_reader.query(sql: <<~SQL)
      WITH RECURSIVE sequence(value) AS (
        SELECT 1 UNION ALL SELECT value + 1 FROM sequence WHERE value < 3
      )
      SELECT value FROM sequence ORDER BY value
    SQL

    assert_equal [[1], [2], [3]], result.fetch(:rows)
  end

  def test_allows_window_functions
    result = @sql_reader.query(sql: <<~SQL)
      SELECT source_track_id, ROW_NUMBER() OVER (ORDER BY source_track_id) AS row_number
      FROM tracks WHERE source_track_id <= 3 ORDER BY source_track_id
    SQL

    assert_equal [[1, 1], [2, 2], [3, 3]], result.fetch(:rows)
  end

  def test_allows_json_functions
    result = @sql_reader.query(sql: "SELECT json_extract('{\"kind\":\"music\"}', '$.kind')")

    assert_equal [['music']], result.fetch(:rows)
  end

  def test_allows_sqlite_schema_introspection
    result = @sql_reader.query(sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name = 'tracks'")

    assert_equal [['tracks']], result.fetch(:rows)
  end

  def test_allows_read_only_introspection_pragmas
    result = @sql_reader.query(sql: 'PRAGMA table_info(tracks)')
    track_key_column = result.fetch(:rows).find { |row| row[1] == 'track_key' }

    refute_nil track_key_column
    assert_equal ['cid', 'name', 'type', 'notnull', 'dflt_value', 'pk'], result.fetch(:columns)
  end

  def test_preserves_duplicate_output_column_names
    result = @sql_reader.query(
      sql: 'SELECT title AS duplicate, artist AS duplicate FROM tracks WHERE source_track_id = 1'
    )

    assert_equal ['duplicate', 'duplicate'], result.fetch(:columns)
    assert_equal [['Old Favorite', 'Aurora']], result.fetch(:rows)
  end

  def test_allows_semicolons_inside_strings_and_one_trailing_terminator
    result = @sql_reader.query(sql: "SELECT ';' AS punctuation;   ")

    assert_equal ['punctuation'], result.fetch(:columns)
    assert_equal [[';']], result.fetch(:rows)
  end

  def test_rejects_comment_only_and_terminator_only_sql_as_invalid_input
    ["-- comment only\n", '/* comment only */', ';'].each do |sql|
      error = assert_raises(Crackdealer::Error) { @sql_reader.query(sql: sql) }

      assert_equal 'invalid_input', error.code
      assert_equal 2, error.exit_status
    end
  end

  def test_applies_result_limit_and_offset_without_rewriting_sql
    result = @sql_reader.query(
      sql: 'SELECT source_track_id FROM tracks ORDER BY source_track_id',
      limit: 3,
      offset: 2
    )

    assert_equal [[3], [4], [5]], result.fetch(:rows)
    assert result.fetch(:truncated)
    complete_result = @sql_reader.query(sql: 'SELECT source_track_id FROM tracks ORDER BY source_track_id', limit: 0)
    assert_equal 10, complete_result.fetch(:rows).length
    refute complete_result.fetch(:truncated)
  end

  def test_encodes_blob_values_as_base64
    result = @sql_reader.query(sql: "SELECT CAST('music' AS BLOB)")

    assert_equal [{ 'base64' => 'bXVzaWM=' }], result.fetch(:rows).map(&:first)
  end

  def test_denies_write_statements_even_when_wrapped_or_commented
    queries = [
      'INSERT INTO tracks (track_key) VALUES (\'new-track\')',
      'UPDATE tracks SET title = \'changed\' WHERE source_track_id = 1',
      'DELETE FROM tracks WHERE source_track_id = 1',
      'DROP TABLE tracks',
      "-- leading comment\nDELETE FROM tracks WHERE source_track_id = 1",
      '/* leading comment */ WITH candidates AS (SELECT track_key FROM tracks) DELETE FROM tracks WHERE track_key IN (SELECT track_key FROM candidates)',
      'CREATE TEMP TABLE scratch(value TEXT)'
    ]

    queries.each { |sql| assert_sql_denied(sql) }
    assert_equal 10, track_count
  end

  def test_denies_attach_and_detach_without_creating_destination
    existing_path = File.join(@temporary_directory, 'existing.sqlite3')
    SQLite3::Database.new(existing_path).close
    missing_path = File.join(@temporary_directory, 'missing.sqlite3')

    assert_sql_denied("ATTACH DATABASE '#{existing_path}' AS attached")
    assert_sql_denied("ATTACH DATABASE '#{missing_path}' AS attached")
    assert_sql_denied('DETACH DATABASE attached')
    refute File.exist?(missing_path)
    assert_equal 10, track_count
  end

  def test_denies_vacuum_into_and_mutable_pragmas
    destination_path = File.join(@temporary_directory, 'vacuum-copy.sqlite3')

    assert_sql_denied("VACUUM INTO '#{destination_path}'")
    assert_sql_denied('PRAGMA user_version = 99')
    assert_sql_denied('PRAGMA journal_mode = WAL')
    refute File.exist?(destination_path)
    assert_equal 1, @database.schema_version
  end

  def test_denies_extension_loading
    assert_sql_denied("SELECT load_extension('untrusted-extension')")
  end

  def test_rejects_multiple_statements_before_executing_any
    error = assert_raises(Crackdealer::Error) do
      @sql_reader.query(sql: 'SELECT 1; DELETE FROM tracks')
    end

    assert_equal 'sql_denied', error.code
    assert_equal 10, track_count
  end

  def test_large_recursive_query_times_out_and_next_read_works
    query = <<~SQL
      WITH RECURSIVE sequence(value) AS (
        SELECT 1 UNION ALL SELECT value + 1 FROM sequence WHERE value < 100000000
      )
      SELECT MAX(value) FROM sequence
    SQL
    error = assert_raises(Crackdealer::Error) do
      @sql_reader.query(sql: query, timeout_ms: 1)
    end

    assert_equal 'query_timeout', error.code
    assert_equal [[10]], @sql_reader.query(sql: 'SELECT COUNT(*) FROM tracks').fetch(:rows)
  end

  def test_rejects_empty_sql_and_invalid_pagination
    assert_equal 'invalid_input', assert_raises(Crackdealer::Error) { @sql_reader.query(sql: '  ') }.code
    assert_equal 'invalid_input', assert_raises(Crackdealer::Error) { @sql_reader.query(sql: 'SELECT 1', limit: -1) }.code
    assert_equal 'invalid_input', assert_raises(Crackdealer::Error) { @sql_reader.query(sql: 'SELECT 1', offset: -1) }.code
  end

  private

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def seed_recommendation
    @database.with_write do |connection|
      connection.execute(
        'INSERT INTO sessions (id, request, context_key, context_json, created_at) VALUES (?, ?, ?, ?, ?)',
        ['session-for-sql', 'Find folk', 'session:session-for-sql', '{}', FIXED_TIME.iso8601(6)]
      )
      recommendation_values = [
        'recommendation-for-sql', 'session-for-sql', 1, 'Aurora', 'History Song', nil, nil, nil,
        'aurora', 'recording-key', 'Fits the request', '[]', FIXED_TIME.iso8601(6)
      ]
      connection.execute(<<~SQL, recommendation_values)
        INSERT INTO recommendations (
          id, session_id, position, artist, title, album, version_label, library_track_key,
          artist_key, recording_key, reason, links_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
    end
  end

  def track_count
    @database.with_read { |connection| connection.get_first_value('SELECT COUNT(*) FROM tracks').to_i }
  end

  def assert_sql_denied(sql)
    error = assert_raises(Crackdealer::Error) { @sql_reader.query(sql: sql) }
    assert_equal 'sql_denied', error.code, "unexpected SQL denial code for #{sql.inspect}"
  end
end
