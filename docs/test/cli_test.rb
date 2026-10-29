require_relative 'test_helper'

class CliTest < CrackdealerTest
  def test_database_override_wins_over_environment
    environment_database_path = File.join(@temporary_directory, 'environment.sqlite3')
    command_database_path = File.join(@temporary_directory, 'command.sqlite3')
    previous_environment_path = ENV['CRACKDEALER_DB']
    ENV['CRACKDEALER_DB'] = environment_database_path

    exit_status, output_json, error_json = run_cli(['--db', command_database_path, 'init'])

    assert_equal 0, exit_status
    assert_equal '', error_json
    assert_equal 1, JSON.parse(output_json).dig('data', 'schema_version')
    assert File.file?(command_database_path)
    refute File.exist?(environment_database_path)
  ensure
    if previous_environment_path
      ENV['CRACKDEALER_DB'] = previous_environment_path
    else
      ENV.delete('CRACKDEALER_DB')
    end
  end

  def test_no_arguments_print_successful_help
    exit_status, output_text, error_text = run_cli([])

    assert_equal 0, exit_status
    assert_match(/Usage:.*crackdealer/, output_text)
    assert_equal "", error_text
  end

  def test_default_path_is_independent_of_cwd
    assert_equal 'constant', defined?(Crackdealer::Database), 'database implementation is not loaded yet'
    expected_path = Crackdealer::Database.default_path

    Dir.chdir(@temporary_directory) do
      assert_equal expected_path, Crackdealer::Database.default_path
    end
  end

  def test_cli_json_errors_and_exit_codes
    exit_status, output_json, error_json = run_cli(['unknown-command'])

    assert_equal 2, exit_status
    assert_equal '', output_json
    error_data = JSON.parse(error_json).fetch('error')
    assert_equal 'invalid_input', error_data.fetch('code')
    assert_match(/command/i, error_data.fetch('message'))
  end

  def test_import_command_returns_counts_and_metadata
    exit_status, output_json, error_json = run_cli([
      '--db',
      @database_path,
      'import',
      File.expand_path('fixtures/library.xml', __dir__)
    ])

    assert_equal 0, exit_status
    assert_equal '', error_json
    result = JSON.parse(output_json)
    assert_equal 10, result.dig('data', 'track_count')
    assert_equal 5, result.dig('data', 'playlist_count')
    assert_equal 1, result.dig('meta', 'schema_version')
    assert_equal result.dig('data', 'imported_at'), result.dig('meta', 'imported_at')
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/, result.dig('meta', 'imported_at'))
  end

  def test_tracks_command_returns_evidence_without_raw_fields
    import_fixture
    exit_status, output_json, error_json = run_cli([
      '--db', @database_path, 'tracks', '--signal', 'unexplored', '--limit', '0'
    ])

    assert_equal 0, exit_status
    assert_equal '', error_json
    result = JSON.parse(output_json)
    rows = result.dig('data', 'rows')
    assert_equal [2, 5, 9], rows.map { |track| track.fetch('source_track_id') }.sort
    assert_equal 0, result.dig('data', 'limit')
    refute result.dig('data', 'truncated')
    refute rows.first.key?('raw_fields_json')
    refute rows.first.key?('raw_fields')
    assert_equal 1, result.dig('meta', 'schema_version')
  end

  def test_playlist_commands_preserve_memberships_and_duplicate_names
    import_fixture
    exit_status, playlists_json, playlists_error = run_cli([
      '--db', @database_path, 'playlists', '--search', 'Shared & Name', '--limit', '0'
    ])

    assert_equal 0, exit_status
    assert_equal '', playlists_error
    playlists = JSON.parse(playlists_json).dig('data', 'rows')
    assert_equal 2, playlists.length
    playlist_key = playlists.find { |playlist| playlist.fetch('source_playlist_id') == 1 }.fetch('playlist_key')

    playlist_status, playlist_json, playlist_error = run_cli([
      '--db', @database_path, 'playlist', playlist_key, '--limit', '0'
    ])

    assert_equal 0, playlist_status
    assert_equal '', playlist_error
    memberships = JSON.parse(playlist_json).dig('data', 'rows')
    assert_equal [1, 2, 4], memberships.map { |membership| membership.fetch('position') }
    assert_equal [1, 1, 6], memberships.map { |membership| membership.fetch('source_track_id') }

    candidates_status, candidates_json, candidates_error = run_cli([
      '--db', @database_path, 'tracks', '--playlist', playlist_key, '--limit', '0'
    ])
    assert_equal 0, candidates_status
    assert_equal '', candidates_error
    candidates = JSON.parse(candidates_json).dig('data', 'rows')
    assert_equal [1, 6], candidates.map { |track| track.fetch('source_track_id') }.sort
  end

  def test_playlist_command_rejects_missing_key
    import_fixture
    exit_status, output_json, error_json = run_cli([
      '--db', @database_path, 'playlist', 'missing-playlist-key'
    ])

    assert_equal 2, exit_status
    assert_equal '', output_json
    assert_equal 'not_found', JSON.parse(error_json).dig('error', 'code')
  end


  def import_fixture
    exit_status, _output_json, error_json = run_cli([
      '--db', @database_path, 'import', File.expand_path('fixtures/library.xml', __dir__)
    ])
    assert_equal 0, exit_status
    assert_equal '', error_json
  end

  def test_sql_file_dash_reads_query_from_stdin
    import_fixture
    exit_status, output_json, error_json = run_cli(
      ['--db', @database_path, 'sql', '--file', '-', '--limit', '5'],
      input: 'SELECT source_track_id FROM tracks ORDER BY source_track_id'
    )

    assert_equal 0, exit_status
    assert_equal '', error_json
    result = JSON.parse(output_json)
    assert_equal ['source_track_id'], result.dig('data', 'columns')
    assert_equal [[1], [2], [3], [4], [5]], result.dig('data', 'rows')
    assert result.dig('data', 'truncated')
    assert_equal 5, result.dig('data', 'returned_count')
  end

  def test_sql_command_does_not_initialize_a_missing_database
    missing_database_path = File.join(@temporary_directory, 'missing-sql.sqlite3')
    exit_status, output_json, error_json = run_cli([
      '--db', missing_database_path, 'sql', '--query', 'SELECT 1'
    ])

    assert_equal 1, exit_status
    assert_equal '', output_json
    assert_equal 'database_error', JSON.parse(error_json).dig('error', 'code')
    refute File.exist?(missing_database_path)
  end

  def test_status_does_not_write_history
    database = build_database
    database.initialize!
    previous_environment_path = ENV['CRACKDEALER_DB']
    ENV['CRACKDEALER_DB'] = @database_path

    exit_status, output_json, error_json = run_cli(['status'])

    assert_equal 0, exit_status
    assert_equal '', error_json
    assert_equal 0, JSON.parse(output_json).dig('data', 'history_counts', 'sessions')
  ensure
    if previous_environment_path
      ENV['CRACKDEALER_DB'] = previous_environment_path
    else
      ENV.delete('CRACKDEALER_DB')
    end
  end

  def test_session_recommendation_history_and_export_commands_work_before_library_import
    exit_status, _init_json, init_error = run_cli(['--db', @database_path, 'init'])
    assert_equal 0, exit_status
    assert_equal '', init_error

    session_status, session_json, session_error = run_cli(
      ['--db', @database_path, 'session', 'add', '--file', '-'],
      input: JSON.generate(request: 'Find a new folk record', context: { seed_artist: 'Aurora' })
    )
    assert_equal 0, session_status
    assert_equal '', session_error
    session = JSON.parse(session_json).fetch('data')
    assert_equal "session:#{session.fetch('id')}", session.fetch('context_key')

    recommendation_status, recommendation_json, recommendation_error = run_cli(
      ['--db', @database_path, 'recommendation', 'add', '--file', '-'],
      input: JSON.generate(
        session_id: session.fetch('id'),
        recommendations: [{
          artist: 'External Artist',
          title: 'External Song',
          reason: 'Similar atmosphere',
          links: [{ service: 'other', url: 'https://example.test/track' }]
        }]
      )
    )
    assert_equal 0, recommendation_status
    assert_equal '', recommendation_error
    recommendation = JSON.parse(recommendation_json).dig('data', 'recommendations').first
    assert_nil recommendation.fetch('library_track_key')
    assert_equal 1, recommendation.fetch('position')

    history_status, history_json, history_error = run_cli([
      '--db', @database_path, 'history', '--session-id', session.fetch('id'), '--limit', '0'
    ])
    assert_equal 0, history_status
    assert_equal '', history_error
    history_rows = JSON.parse(history_json).dig('data', 'rows')
    assert_equal [recommendation.fetch('id')], history_rows.map { |row| row.fetch('id') }
    assert_equal({ 'seed_artist' => 'Aurora' }, history_rows.first.fetch('context'))

    export_status, export_json, export_error = run_cli(['--db', @database_path, 'history', 'export'])
    assert_equal 0, export_status
    assert_equal '', export_error
    exported_data = JSON.parse(export_json).fetch('data')
    assert_equal [session.fetch('id')], exported_data.fetch('sessions').map { |row| row.fetch('id') }
    assert_equal [recommendation.fetch('id')], exported_data.fetch('recommendations').map { |row| row.fetch('id') }
    assert_equal [], exported_data.fetch('feedback_events')

    status_exit, status_json, status_error = run_cli(['--db', @database_path, 'status'])
    assert_equal 0, status_exit
    assert_equal '', status_error
    assert_equal 1, JSON.parse(status_json).dig('data', 'history_counts', 'sessions')
    assert_equal 1, JSON.parse(status_json).dig('data', 'history_counts', 'recommendations')
  end

  def test_session_add_rejects_missing_request_with_cli_error_envelope
    exit_status, output_json, error_json = run_cli(
      ['--db', @database_path, 'session', 'add', '--file', '-'],
      input: JSON.generate(context: { seed_artist: 'Aurora' })
    )

    assert_equal 2, exit_status
    assert_equal '', output_json
    error_data = JSON.parse(error_json).fetch('error')
    assert_equal 'invalid_input', error_data.fetch('code')
    assert_match(/request/i, error_data.fetch('message'))
  end

  def test_feedback_commands_add_list_and_retract_events
    run_cli(['--db', @database_path, 'init'])
    session_status, session_json, session_error = run_cli(
      ['--db', @database_path, 'session', 'add', '--file', '-'],
      input: JSON.generate(request: 'Find a live folk performance', context_key: 'playlist:live-folk')
    )
    assert_equal 0, session_status
    assert_equal '', session_error
    session_id = JSON.parse(session_json).dig('data', 'id')

    recommendation_status, recommendation_json, recommendation_error = run_cli(
      ['--db', @database_path, 'recommendation', 'add', '--file', '-'],
      input: JSON.generate(
        session_id: session_id,
        recommendations: [{ artist: 'Live Artist', title: 'Live Song', reason: 'A compelling live version' }]
      )
    )
    assert_equal 0, recommendation_status
    assert_equal '', recommendation_error
    recommendation_id = JSON.parse(recommendation_json).dig('data', 'recommendations', 0, 'id')

    add_status, add_json, add_error = run_cli(
      ['--db', @database_path, 'feedback', 'add', '--file', '-'],
      input: JSON.generate(recommendation_id: recommendation_id, reaction: 'dont_recommend', scope: 'track')
    )
    assert_equal 0, add_status
    assert_equal '', add_error
    event_id = JSON.parse(add_json).dig('data', 'id')

    list_status, list_json, list_error = run_cli([
      '--db', @database_path, 'feedback', 'list', '--recommendation-id', recommendation_id, '--limit', '0'
    ])
    assert_equal 0, list_status
    assert_equal '', list_error
    assert_equal ['dont_recommend'], JSON.parse(list_json).dig('data', 'rows').map { |row| row.fetch('reaction') }

    retract_status, retract_json, retract_error = run_cli(['--db', @database_path, 'feedback', 'retract', event_id])
    assert_equal 0, retract_status
    assert_equal '', retract_error
    assert_equal 'retraction', JSON.parse(retract_json).dig('data', 'event_type')

    empty_status, empty_json, empty_error = run_cli([
      '--db', @database_path, 'feedback', 'list', '--recommendation-id', recommendation_id
    ])
    assert_equal 0, empty_status
    assert_equal '', empty_error
    assert_empty JSON.parse(empty_json).dig('data', 'rows')
  end

  def test_schema_lists_feedback_tables_before_history
    database = build_database
    database.initialize!
    previous_environment_path = ENV['CRACKDEALER_DB']
    ENV['CRACKDEALER_DB'] = @database_path

    exit_status, output_json, error_json = run_cli(['schema'])

    assert_equal 0, exit_status
    assert_equal '', error_json
    schema_tables = JSON.parse(output_json).dig('data', 'tables').map { |table| table.fetch('name') }
    assert_includes schema_tables, 'feedback_events'
    assert_includes schema_tables, 'recommendations'
    assert_includes schema_tables, 'sessions'
  ensure
    if previous_environment_path
      ENV['CRACKDEALER_DB'] = previous_environment_path
    else
      ENV.delete('CRACKDEALER_DB')
    end
  end
end
