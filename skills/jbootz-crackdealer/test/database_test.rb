require_relative 'test_helper'

class DatabaseTest < CrackdealerTest
  CONTRACTED_TABLES = %w[
    feedback_events
    library_import
    playlist_tracks
    playlists
    recommendations
    sessions
    tracks
  ].freeze

  def test_init_is_idempotent
    database = build_database

    2.times { database.initialize! }

    table_names = database.with_read do |connection|
      connection.execute(
        "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      ).map { |row| row.fetch('name') }
    end
    assert_equal CONTRACTED_TABLES, table_names
    assert_equal 1, database.schema_version
  end

  def test_read_missing_database_does_not_create_file
    database = build_database

    error = assert_raises(Crackdealer::Error) do
      database.with_read { |connection| connection.execute('SELECT 1') }
    end

    assert_equal 'database_error', error.code
    refute File.exist?(@database_path)
  end

  def test_newer_schema_is_rejected
    SQLite3::Database.new(@database_path) do |connection|
      connection.execute('PRAGMA user_version = 2')
    end
    database = build_database

    error = assert_raises(Crackdealer::Error) { database.initialize! }

    assert_equal 'database_error', error.code
    assert_match(/newer|unsupported/i, error.message)
  end

  def test_foreign_keys_are_enforced
    database = build_database
    database.initialize!

    error = assert_raises(SQLite3::ConstraintException) do
      database.with_write do |connection|
        connection.execute(
          'INSERT INTO playlist_tracks (playlist_key, position, track_key) VALUES (?, ?, ?)',
          ['missing-playlist', 1, 'missing-track']
        )
      end
    end

    assert_match(/foreign key/i, error.message)
  end
end
