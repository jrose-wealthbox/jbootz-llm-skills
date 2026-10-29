require_relative 'test_helper'
require 'time'

class HistoryTest < CrackdealerTest
  FIXED_TIME = Time.iso8601('2026-10-23T12:00:00Z').freeze

  def setup
    super
    assert_equal 'constant', defined?(Crackdealer::History), 'history implementation is not loaded yet'
    @database = build_database
    @database.initialize!
    @current_time = FIXED_TIME
    @history = Crackdealer::History.new(database: @database, clock: -> { @current_time })
  end

  def test_records_external_track_without_library_row
    session = @history.create_session(request: 'Find more spooky folk')
    records = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload]
    )

    assert_nil records.first.fetch(:library_track_key)
    assert_equal 1, records.first.fetch(:position)
    assert_equal 'New Artist', records.first.fetch(:artist)
    assert_match(/\A[0-9a-f-]{36}\z/, records.first.fetch(:id))
  end

  def test_context_defaults_to_session_but_accepts_playlist_context
    default_session = @history.create_session(request: 'Try an unfamiliar folk record', context: { seed_artist: 'Aurora' })
    playlist_session = @history.create_session(
      request: 'Extend this playlist',
      context_key: 'playlist:playlist-one',
      context: { playlist_key: 'playlist-one' }
    )

    assert_equal "session:#{default_session.fetch(:id)}", default_session.fetch(:context_key)
    assert_equal({ 'seed_artist' => 'Aurora' }, default_session.fetch(:context))
    assert_equal 'playlist:playlist-one', playlist_session.fetch(:context_key)
    assert_equal({ 'playlist_key' => 'playlist-one' }, playlist_session.fetch(:context))
  end

  def test_rejects_false_context_key_instead_of_using_default
    error = assert_raises(Crackdealer::Error) do
      @history.create_session(request: 'Find folk', context_key: false)
    end

    assert_equal 'invalid_input', error.code
  end

  def test_batch_is_atomic_and_positions_append
    session = @history.create_session(request: 'Find folk')
    first_batch = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload, recommendation_payload(title: 'Second Song')]
    )
    second_batch = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload(title: 'Third Song')]
    )

    assert_equal [1, 2], first_batch.map { |row| row.fetch(:position) }
    assert_equal [3], second_batch.map { |row| row.fetch(:position) }
    assert_equal 3, recommendation_count

    assert_raises(Crackdealer::Error) do
      @history.add_recommendations(
        session_id: session.fetch(:id),
        recommendations: [recommendation_payload(title: 'Would Roll Back'), recommendation_payload(reason: ' ')]
      )
    end
    assert_equal 3, recommendation_count
  end

  def test_recording_key_ignores_album_but_preserves_live_version
    session = @history.create_session(request: 'Compare versions')
    records = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [
        recommendation_payload(title: 'Evening Song', album: 'Original Album'),
        recommendation_payload(title: 'Evening Song', album: 'Compilation'),
        recommendation_payload(title: 'Evening Song', version_label: 'Live at the Hall')
      ]
    )

    assert_equal records[0].fetch(:recording_key), records[1].fetch(:recording_key)
    refute_equal records[0].fetch(:recording_key), records[2].fetch(:recording_key)
    assert_equal 'new artist', records.first.fetch(:artist_key)
  end

  def test_reimport_and_track_removal_preserve_history
    import_fixture('library.xml')
    session = @history.create_session(request: 'Remember this library track')
    removed_track_key = 'apple_music:AAAAAAAAAAAAAAAA:0000000000000003'
    changed_source_id_key = 'apple_music:AAAAAAAAAAAAAAAA:0000000000000001'
    @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [
        recommendation_payload(title: 'Removed from library', library_track_key: removed_track_key),
        recommendation_payload(title: 'Source ID changed', library_track_key: changed_source_id_key)
      ]
    )

    import_fixture('library_updated.xml')
    rows = @history.list(session_id: session.fetch(:id), limit: 0).fetch(:rows)

    assert_equal [changed_source_id_key, removed_track_key].sort,
      rows.map { |row| row.fetch('library_track_key') }.sort
    assert_equal 9, track_count
    assert_equal changed_source_id_key, find_library_track(source_track_id: 101).fetch('track_key')
    assert_nil find_library_track(source_track_id: 3)
  end

  def test_optional_library_association_is_validated
    import_fixture('library.xml')
    session = @history.create_session(request: 'Reuse a favorite')
    track_key = 'apple_music:AAAAAAAAAAAAAAAA:0000000000000001'
    valid_record = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload(library_track_key: track_key)]
    ).first

    assert_equal track_key, valid_record.fetch(:library_track_key)
    error = assert_raises(Crackdealer::Error) do
      @history.add_recommendations(
        session_id: session.fetch(:id),
        recommendations: [recommendation_payload(library_track_key: 'missing-library-track')]
      )
    end
    assert_equal 'invalid_input', error.code
    assert_equal 1, recommendation_count
  end

  def test_history_filters_and_pagination
    first_session = @history.create_session(request: 'First context', context_key: 'playlist:one')
    first_record = @history.add_recommendations(
      session_id: first_session.fetch(:id),
      recommendations: [recommendation_payload(title: 'First Song')]
    ).first
    @current_time += 1
    second_session = @history.create_session(request: 'Second context', context_key: 'playlist:two')
    second_record = @history.add_recommendations(
      session_id: second_session.fetch(:id),
      recommendations: [
        recommendation_payload(title: 'Second Song'),
        recommendation_payload(artist: 'Other Artist', title: 'Other Song')
      ]
    )

    all_rows = @history.list(limit: 0).fetch(:rows)
    assert_equal [second_record[1].fetch(:id), second_record[0].fetch(:id), first_record.fetch(:id)], all_rows.map { |row| row.fetch('id') }
    page = @history.list(limit: 1, offset: 1)
    assert_equal [second_record[0].fetch(:id)], page.fetch(:rows).map { |row| row.fetch('id') }
    assert page.fetch(:truncated)
    assert_equal [first_record.fetch(:id)], @history.list(session_id: first_session.fetch(:id), limit: 0).fetch(:rows).map { |row| row.fetch('id') }
    assert_equal [first_record.fetch(:id)], @history.list(context_key: 'playlist:one', limit: 0).fetch(:rows).map { |row| row.fetch('id') }
    assert_equal [second_record[0].fetch(:id), first_record.fetch(:id)],
      @history.list(artist: '  NEW   ARTIST ', limit: 0).fetch(:rows).map { |row| row.fetch('id') }
    assert_equal [first_record.fetch(:id)],
      @history.list(recording_key: first_record.fetch(:recording_key), limit: 0).fetch(:rows).map { |row| row.fetch('id') }
  end

  def test_bad_payload_does_not_write_partial_history
    session = @history.create_session(request: 'Find music')
    error = assert_raises(Crackdealer::Error) do
      @history.add_recommendations(
        session_id: session.fetch(:id),
        recommendations: [recommendation_payload, { artist: 'Missing Title', reason: 'bad row' }]
      )
    end

    assert_equal 'invalid_input', error.code
    assert_equal 0, recommendation_count
    missing_session_error = assert_raises(Crackdealer::Error) do
      @history.add_recommendations(session_id: 'missing-session', recommendations: [recommendation_payload])
    end
    assert_equal 'not_found', missing_session_error.code
  end

  def test_links_require_known_services_and_http_urls_without_partial_writes
    session = @history.create_session(request: 'Find a verified listening link')
    error = assert_raises(Crackdealer::Error) do
      @history.add_recommendations(
        session_id: session.fetch(:id),
        recommendations: [
          recommendation_payload(links: [{ service: 'spotify', url: 'https://open.spotify.com/track/demo' }]),
          recommendation_payload(title: 'Invalid Link', links: [{ service: 'demo', url: 'javascript:alert(1)' }])
        ]
      )
    end

    assert_equal 'invalid_input', error.code
    assert_equal 0, recommendation_count
  end

  def test_empty_recommendation_batch_is_rejected
    session = @history.create_session(request: 'Find a song')
    error = assert_raises(Crackdealer::Error) do
      @history.add_recommendations(session_id: session.fetch(:id), recommendations: [])
    end

    assert_equal 'invalid_input', error.code
    assert_equal 0, recommendation_count
  end

  def test_export_contains_all_durable_rows_including_empty_tables
    empty_export = @history.export
    assert_equal 1, empty_export.fetch(:export_format_version)
    assert_equal [], empty_export.fetch(:sessions)
    assert_equal [], empty_export.fetch(:recommendations)
    assert_equal [], empty_export.fetch(:feedback_events)

    session = @history.create_session(request: 'Save a suggestion', context: { note: 'portable' })
    recommendation = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload(links: [{ service: 'other', url: 'https://example.test/song' }])]
    ).first
    @database.with_write do |connection|
      connection.execute(<<~SQL, ['event-one', recommendation.fetch(:id), FIXED_TIME.iso8601(6)])
        INSERT INTO feedback_events (id, recommendation_id, event_type, reaction, scope, note, retracts_event_id, created_at)
        VALUES (?, ?, 'reaction', 'liked', 'context', NULL, NULL, ?)
      SQL
    end
    export_data = @history.export

    assert_equal [session.fetch(:id)], export_data.fetch(:sessions).map { |row| row.fetch('id') }
    assert_equal [recommendation.fetch(:id)], export_data.fetch(:recommendations).map { |row| row.fetch('id') }
    assert_equal ['event-one'], export_data.fetch(:feedback_events).map { |row| row.fetch('id') }
    assert_equal({ 'note' => 'portable' }, JSON.parse(export_data.fetch(:sessions).first.fetch('context_json')))
    assert_equal [{ 'service' => 'other', 'url' => 'https://example.test/song' }],
      JSON.parse(export_data.fetch(:recommendations).first.fetch('links_json'))
  end

  private

  def recommendation_payload(artist: 'New Artist', title: 'New Song', album: nil, version_label: nil,
                             library_track_key: nil, reason: 'Fits the requested atmosphere', links: [])
    {
      artist: artist,
      title: title,
      album: album,
      version_label: version_label,
      library_track_key: library_track_key,
      reason: reason,
      links: links
    }
  end

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def import_fixture(name)
    Crackdealer::Importer.new(database: @database, clock: -> { FIXED_TIME }).import(path: fixture_path(name))
  end

  def recommendation_count
    @database.with_read { |connection| connection.get_first_value('SELECT COUNT(*) FROM recommendations').to_i }
  end

  def track_count
    @database.with_read { |connection| connection.get_first_value('SELECT COUNT(*) FROM tracks').to_i }
  end

  def find_library_track(source_track_id:)
    @database.with_read do |connection|
      connection.get_first_row('SELECT track_key FROM tracks WHERE source_track_id = ?', [source_track_id])
    end
  end
end
