require_relative 'test_helper'
require 'open3'
require 'rbconfig'

class AcceptanceTest < CrackdealerTest
  def test_end_to_end_import_recommendation_feedback_refresh_and_sql
    init_result = run_success('init')
    assert_equal 1, init_result.dig('data', 'schema_version')

    import_result = run_success('import', fixture_path('library.xml'))
    assert_equal 10, import_result.dig('data', 'track_count')
    assert_equal 5, import_result.dig('data', 'playlist_count')

    positive_tracks = run_success('tracks', '--signal', 'positive', '--limit', '0').dig('data', 'rows')
    underplayed_tracks = run_success('tracks', '--signal', 'unexplored', '--limit', '0').dig('data', 'rows')
    assert_includes positive_tracks.map { |track| track.fetch('source_track_id') }, 1
    assert_equal [2, 5, 9], underplayed_tracks.map { |track| track.fetch('source_track_id') }.sort

    playlists = run_success('playlists', '--search', 'Shared & Name', '--limit', '0').dig('data', 'rows')
    playlist_key = playlists.find { |playlist| playlist.fetch('source_playlist_id') == 1 }.fetch('playlist_key')
    membership = run_success('playlist', playlist_key, '--limit', '0').dig('data', 'rows')
    assert_equal [1, 2, 4], membership.map { |row| row.fetch('position') }
    assert_equal [1, 1, 6], membership.map { |row| row.fetch('source_track_id') }

    first_session = run_success(
      'session', 'add', '--file', '-',
      input: JSON.generate(request: 'Find a new folk song', context_key: "playlist:#{playlist_key}", context: { playlist_key: playlist_key })
    ).fetch('data')
    first_recommendation = run_success(
      'recommendation', 'add', '--file', '-',
      input: JSON.generate(
        session_id: first_session.fetch('id'),
        recommendations: [{
          artist: 'External Artist',
          title: 'External Song',
          reason: 'It shares the quiet folk quality of library favorites',
          links: []
        }]
      )
    ).dig('data', 'recommendations').first
    assert_nil first_recommendation.fetch('library_track_key')

    liked_event = add_feedback(first_recommendation.fetch('id'), 'liked')
    known_event = add_feedback(first_recommendation.fetch('id'), 'already_known')
    assert_equal [liked_event.fetch('id'), known_event.fetch('id')].sort,
      run_success('feedback', 'list', '--recommendation-id', first_recommendation.fetch('id'), '--limit', '0')
        .dig('data', 'rows').map { |row| row.fetch('id') }.sort

    second_session = run_success(
      'session', 'add', '--file', '-',
      input: JSON.generate(request: 'Try this artist in another setting', context: { seed_artist: 'External Artist' })
    ).fetch('data')
    second_recommendation = run_success(
      'recommendation', 'add', '--file', '-',
      input: JSON.generate(
        session_id: second_session.fetch('id'),
        recommendations: [{ artist: 'External Artist', title: 'External Song', reason: 'A different context', links: [] }]
      )
    ).dig('data', 'recommendations').first
    assert_empty run_success(
      'feedback', 'list', '--recommendation-id', second_recommendation.fetch('id'), '--limit', '0'
    ).dig('data', 'rows')

    exclusion_event = add_feedback(first_recommendation.fetch('id'), 'dont_recommend', scope: 'track')
    matching_feedback = run_success(
      'feedback', 'list', '--recommendation-id', second_recommendation.fetch('id'), '--limit', '0'
    ).dig('data', 'rows')
    assert_includes matching_feedback.map { |row| row.fetch('id') }, exclusion_event.fetch('id')

    updated_import = run_success('import', fixture_path('library_updated.xml'))
    assert_equal 9, updated_import.dig('data', 'track_count')
    assert_equal [first_recommendation.fetch('id'), second_recommendation.fetch('id')].sort,
      run_success('history', '--limit', '0').dig('data', 'rows').map { |row| row.fetch('id') }.sort
    assert_includes run_success(
      'feedback', 'list', '--recommendation-id', second_recommendation.fetch('id'), '--limit', '0'
    ).dig('data', 'rows').map { |row| row.fetch('reaction') }, 'dont_recommend'

    retraction = run_success('feedback', 'retract', exclusion_event.fetch('id')).fetch('data')
    assert_equal 'retraction', retraction.fetch('event_type')
    refute_includes run_success(
      'feedback', 'list', '--recommendation-id', second_recommendation.fetch('id'), '--limit', '0'
    ).dig('data', 'rows').map { |row| row.fetch('reaction') }, 'dont_recommend'

    sql_result = run_success(
      'sql', '--query', <<~SQL, '--limit', '5'
        SELECT COUNT(DISTINCT tracks.track_key) AS library_tracks,
          COUNT(DISTINCT playlists.playlist_key) AS playlists,
          COUNT(DISTINCT recommendations.id) AS recommendations,
          COUNT(DISTINCT feedback_events.id) AS feedback_events
        FROM tracks
        LEFT JOIN playlist_tracks ON playlist_tracks.track_key = tracks.track_key
        LEFT JOIN playlists ON playlists.playlist_key = playlist_tracks.playlist_key
        LEFT JOIN recommendations ON recommendations.library_track_key = tracks.track_key
        LEFT JOIN feedback_events ON feedback_events.recommendation_id = recommendations.id
      SQL
    ).dig('data', 'rows').first
    assert_equal [9, 4, 0, 0], sql_result

    exported = run_success('history', 'export').fetch('data')
    assert_equal 2, exported.fetch('sessions').length
    assert_equal 2, exported.fetch('recommendations').length
    assert_equal 4, exported.fetch('feedback_events').length

    status, stdout, stderr = run_process('sql', '--query', "DELETE FROM tracks WHERE source_track_id = 1")
    assert_equal 2, status
    assert_equal '', stdout
    assert_equal 'sql_denied', JSON.parse(stderr).dig('error', 'code')
    assert_equal 9, run_success('status').dig('data', 'track_count')
  end

  private

  def run_success(*arguments, input: '')
    status, stdout, stderr = run_process(*arguments, input: input)
    assert_equal 0, status, "CLI failed for #{arguments.first}: #{stderr}"
    assert_equal '', stderr
    JSON.parse(stdout)
  end

  def run_process(*arguments, input: '')
    stdout, stderr, process_status = Open3.capture3(
      RbConfig.ruby,
      File.expand_path('../bin/crackdealer', __dir__),
      '--db',
      @database_path,
      *arguments,
      stdin_data: input
    )
    [process_status.exitstatus, stdout, stderr]
  end

  def add_feedback(recommendation_id, reaction, scope: 'context')
    run_success(
      'feedback', 'add', '--file', '-',
      input: JSON.generate(recommendation_id: recommendation_id, reaction: reaction, scope: scope)
    ).fetch('data')
  end

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
