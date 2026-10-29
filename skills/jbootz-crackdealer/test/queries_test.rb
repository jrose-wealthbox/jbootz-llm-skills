require_relative 'test_helper'
require 'time'

class QueriesTest < CrackdealerTest
  FIXED_TIME = Time.iso8601('2026-10-23T12:00:00Z').freeze

  def setup
    super
    assert_equal 'constant', defined?(Crackdealer::Queries), 'query implementation is not loaded yet'
    @database = build_database
    @database.initialize!
    importer = Crackdealer::Importer.new(database: @database, clock: -> { FIXED_TIME })
    importer.import(path: fixture_path('library.xml'))
    @queries = Crackdealer::Queries.new(database: @database, clock: -> { FIXED_TIME })
  end

  def test_positive_and_negative_evidence_can_coexist
    track = track_result(source_track_id: 4)

    refute track.fetch('explicit_positive')
    assert track.fetch('explicit_negative')
    assert track.fetch('loved_positive')
    assert track.fetch('frequent_play')
  end

  def test_computed_rating_is_not_explicit_preference
    track = track_result(source_track_id: 5)

    refute track.fetch('explicit_positive')
    assert track.fetch('unexplored_candidate')
    assert_equal 1, track.fetch('rating_computed')
  end

  def test_manual_membership_counts_distinct_playlists
    track = track_result(source_track_id: 1)

    assert_equal 2, track.fetch('manual_playlist_count')
  end

  def test_smart_and_system_playlists_do_not_imply_manual_curation
    smart_track = track_result(source_track_id: 5)
    system_only_track = track_result(source_track_id: 8, include_nonmusic: true)

    assert_equal 0, smart_track.fetch('manual_playlist_count')
    assert_equal 0, system_only_track.fetch('manual_playlist_count')
  end

  def test_unexplored_is_weak_evidence
    unexplored_ids = @queries.tracks(signal: 'unexplored').fetch(:rows).map do |track|
      track.fetch('source_track_id')
    end

    assert_equal [2, 5, 9], unexplored_ids.sort
  end

  def test_stale_boundary_and_missing_time
    favorite = track_result(source_track_id: 1)
    cutoff_track = track_result(source_track_id: 6)
    missing_time_track = track_result(source_track_id: 7)

    assert favorite.fetch('stale_play')
    refute cutoff_track.fetch('stale_play')
    refute missing_time_track.fetch('stale_play')
    assert_equal [1], @queries.tracks(signal: 'rediscover').fetch(:rows).map { |track| track.fetch('source_track_id') }
  end

  def test_filters_intersect
    tracks = @queries.tracks(signal: 'negative', artist: 'Aurora', search: 'Explicit Reject')
      .fetch(:rows)

    assert_equal [3], tracks.map { |track| track.fetch('source_track_id') }
  end

  def test_search_handles_unicode_quotes_and_literal_wildcards
    xml = File.read(fixture_path('library.xml')).sub('Neutral Three', 'Neutral 100%_ Three')
    variant_path = write_xml('wildcard-library.xml', xml)
    importer = Crackdealer::Importer.new(database: @database, clock: -> { FIXED_TIME })
    importer.import(path: variant_path)

    percent_matches = @queries.tracks(search: '%').fetch(:rows)
    underscore_matches = @queries.tracks(search: '_').fetch(:rows)
    combined_matches = @queries.tracks(search: '100%_').fetch(:rows)
    unicode_matches = @queries.tracks(artist: 'BJÖRK').fetch(:rows)
    quoted_matches = @queries.tracks(search: "' OR 1=1 --").fetch(:rows)

    assert_equal [10], percent_matches.map { |track| track.fetch('source_track_id') }
    assert_equal [10], underscore_matches.map { |track| track.fetch('source_track_id') }
    assert_equal [10], combined_matches.map { |track| track.fetch('source_track_id') }
    assert_equal [5], unicode_matches.map { |track| track.fetch('source_track_id') }
    assert_empty quoted_matches
  end

  def test_playlist_preserves_repeated_tracks_and_order
    playlist_key = find_playlist_key(source_playlist_id: 1)
    result = @queries.playlist(playlist_key: playlist_key, limit: 0)

    assert_equal [1, 2, 4], result.fetch(:rows).map { |track| track.fetch('position') }
    assert_equal [1, 1, 6], result.fetch(:rows).map { |track| track.fetch('source_track_id') }
    refute result.fetch(:truncated)
  end

  def test_pagination_is_stable_and_reports_truncation
    complete_rows = @queries.tracks(limit: 0).fetch(:rows)
    page = @queries.tracks(limit: 3, offset: 2)

    assert_equal complete_rows.slice(2, 3), page.fetch(:rows)
    assert page.fetch(:truncated)
    assert_equal 0, @queries.tracks(limit: 3, offset: 20).fetch(:rows).length
  end

  def test_nonmusic_is_available_only_when_requested
    default_ids = @queries.tracks(limit: 0).fetch(:rows).map { |track| track.fetch('source_track_id') }
    all_ids = @queries.tracks(limit: 0, include_nonmusic: true).fetch(:rows).map do |track|
      track.fetch('source_track_id')
    end

    refute_includes default_ids, 8
    assert_includes all_ids, 8
  end

  def test_playlist_filter_returns_distinct_track_candidates
    playlist_key = find_playlist_key(source_playlist_id: 1)

    tracks = @queries.tracks(playlist_key: playlist_key, limit: 0).fetch(:rows)

    assert_equal [1, 6], tracks.map { |track| track.fetch('source_track_id') }.sort
  end

  def test_nonexistent_playlist_key_is_not_found
    error = assert_raises(Crackdealer::Error) do
      @queries.tracks(playlist_key: 'missing-playlist-key')
    end

    assert_equal 'not_found', error.code
  end

  def test_invalid_thresholds_are_rejected
    error = assert_raises(Crackdealer::Error) { @queries.tracks(frequent_play_count: 0) }

    assert_equal 'invalid_input', error.code
    assert_raises(Crackdealer::Error) { @queries.tracks(low_play_count: -1) }
    assert_raises(Crackdealer::Error) { @queries.tracks(stale_days: -1) }
  end

  private

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def track_result(source_track_id:, include_nonmusic: false)
    @queries.tracks(include_nonmusic: include_nonmusic, limit: 0).fetch(:rows)
      .find { |track| track.fetch('source_track_id') == source_track_id }
  end

  def find_playlist_key(source_playlist_id:)
    @database.with_read do |connection|
      connection.get_first_value('SELECT playlist_key FROM playlists WHERE source_playlist_id = ?', source_playlist_id)
    end
  end

  def write_xml(name, content)
    xml_path = File.join(@temporary_directory, name)
    File.write(xml_path, content)
    xml_path
  end
end
