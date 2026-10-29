require_relative 'test_helper'
require 'time'

class FeedbackTest < CrackdealerTest
  FIXED_TIME = Time.iso8601('2026-10-23T12:00:00Z').freeze

  def setup
    super
    assert_equal 'constant', defined?(Crackdealer::Feedback), 'feedback implementation is not loaded yet'
    @database = build_database
    @database.initialize!
    @current_time = FIXED_TIME
    clock = -> { @current_time }
    @history = Crackdealer::History.new(database: @database, clock: clock)
    @feedback = Crackdealer::Feedback.new(database: @database, clock: clock)
  end

  def test_known_liked_and_wrong_fit_can_coexist
    _session, recommendation = record_recommendation
    liked = @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'liked')
    wrong_fit = @feedback.add(
      recommendation_id: recommendation.fetch(:id),
      reaction: 'wrong_fit',
      note: 'Good artist, wrong mood for that request'
    )

    assert_equal 'context', liked.fetch(:scope)
    assert_equal 'wrong_fit', wrong_fit.fetch(:reaction)
    assert_equal %w[liked wrong_fit], effective_rows(recommendation.fetch(:id)).map { |row| row.fetch('reaction') }.sort
    assert_equal 'playlist:autumn-mix', effective_rows(recommendation.fetch(:id)).first.fetch('origin_context_key')
  end

  def test_default_feedback_does_not_leak_into_other_contexts
    first_session, first_recommendation = record_recommendation(context_key: 'playlist:first')
    _second_session, second_recommendation = record_recommendation(context_key: 'playlist:second')
    @feedback.add(recommendation_id: first_recommendation.fetch(:id), reaction: 'wrong_fit')

    assert_equal [first_session.fetch(:id)], effective_rows(first_recommendation.fetch(:id)).map { |row| row.fetch('session_id') }.uniq
    assert_empty effective_rows(second_recommendation.fetch(:id))
  end

  def test_playlist_context_is_reused_across_sessions
    shared_context = 'playlist:late-night-folk'
    _first_session, first_recommendation = record_recommendation(context_key: shared_context)
    _second_session, second_recommendation = record_recommendation(context_key: shared_context)
    @feedback.add(recommendation_id: first_recommendation.fetch(:id), reaction: 'dont_recommend')

    rows = effective_rows(second_recommendation.fetch(:id))
    assert_equal ['dont_recommend'], rows.map { |row| row.fetch('reaction') }
    assert_equal [first_recommendation.fetch(:id)], rows.map { |row| row.fetch('recommendation_id') }
  end

  def test_track_scope_applies_to_same_recording_in_other_sessions
    _first_session, first_recommendation = record_recommendation(album: 'Original Album')
    _second_session, second_recommendation = record_recommendation(album: 'Compilation')
    @feedback.add(recommendation_id: first_recommendation.fetch(:id), reaction: 'already_known', scope: 'track')

    assert_equal ['already_known'], effective_rows(second_recommendation.fetch(:id)).map { |row| row.fetch('reaction') }
  end

  def test_artist_scope_applies_to_other_tracks_by_artist
    _first_session, first_recommendation = record_recommendation(title: 'First Song')
    _same_artist_session, same_artist_recommendation = record_recommendation(title: 'Different Song')
    _other_artist_session, other_artist_recommendation = record_recommendation(artist: 'Other Artist', title: 'Another Song')
    @feedback.add(recommendation_id: first_recommendation.fetch(:id), reaction: 'dont_recommend', scope: 'artist')

    assert_equal ['dont_recommend'], effective_rows(same_artist_recommendation.fetch(:id)).map { |row| row.fetch('reaction') }
    assert_empty effective_rows(other_artist_recommendation.fetch(:id))
  end

  def test_prospective_candidate_lookup_does_not_create_history
    _session, recommendation = record_recommendation(context_key: 'playlist:origin')
    @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'liked', scope: 'track')
    @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'wrong_fit', scope: 'context')
    counts_before = durable_counts

    result = @feedback.effective_for(artist: '  NEW ARTIST ', title: 'New Song')

    assert_equal ['liked'], result.fetch(:rows).map { |row| row.fetch('reaction') }
    assert_equal counts_before, durable_counts
    assert_equal 'playlist:origin', result.fetch(:rows).first.fetch('origin_context_key')
  end

  def test_retraction_keeps_audit_history_but_removes_effect
    _session, recommendation = record_recommendation
    reaction = @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'disliked', scope: 'track')
    retraction = @feedback.retract(event_id: reaction.fetch(:id))

    assert_equal 'retraction', retraction.fetch(:event_type)
    assert_equal 'track', retraction.fetch(:scope)
    assert_empty effective_rows(recommendation.fetch(:id))
    assert_equal 2, feedback_event_count
    assert_equal %w[reaction retraction], @history.export.fetch(:feedback_events).map { |row| row.fetch('event_type') }.sort
    assert_empty @history.list(session_id: recommendation.fetch(:session_id), limit: 0)
      .fetch(:rows).first.fetch('feedback_events')
  end

  def test_duplicate_retraction_and_retracting_a_retraction_are_rejected
    _session, recommendation = record_recommendation
    reaction = @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'liked')
    retraction = @feedback.retract(event_id: reaction.fetch(:id))
    duplicate_error = assert_raises(Crackdealer::Error) { @feedback.retract(event_id: reaction.fetch(:id)) }
    second_order_error = assert_raises(Crackdealer::Error) { @feedback.retract(event_id: retraction.fetch(:id)) }

    assert_equal 'invalid_input', duplicate_error.code
    assert_equal 'invalid_input', second_order_error.code
    assert_equal 2, feedback_event_count
  end

  def test_note_requires_text
    _session, recommendation = record_recommendation
    [nil, '   '].each do |note|
      error = assert_raises(Crackdealer::Error) do
        @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'note', note: note)
      end
      assert_equal 'invalid_input', error.code
    end

    event = @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'note', note: 'Try this in winter')
    assert_equal 'Try this in winter', event.fetch(:note)
  end

  def test_unimported_recommendation_accepts_feedback
    _session, recommendation = record_recommendation

    assert_nil recommendation.fetch(:library_track_key)
    event = @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'liked')

    assert_equal recommendation.fetch(:id), event.fetch(:recommendation_id)
    assert_equal ['liked'], effective_rows(recommendation.fetch(:id)).map { |row| row.fetch('reaction') }
  end

  def test_import_cannot_erase_feedback
    importer = Crackdealer::Importer.new(database: @database, clock: -> { FIXED_TIME })
    importer.import(path: fixture_path('library.xml'))
    session = @history.create_session(request: 'Avoid this track', context_key: 'playlist:shared')
    removed_track_key = 'apple_music:AAAAAAAAAAAAAAAA:0000000000000003'
    recommendation = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload(
        artist: 'Aurora', title: 'Explicit Reject & Leave', library_track_key: removed_track_key
      )]
    ).first
    event = @feedback.add(
      recommendation_id: recommendation.fetch(:id), reaction: 'dont_recommend', scope: 'track'
    )

    importer.import(path: fixture_path('library_updated.xml'))

    assert_nil find_library_track(removed_track_key)
    assert_equal [event.fetch(:id)], effective_rows(recommendation.fetch(:id)).map { |row| row.fetch('id') }
    assert_equal 1, feedback_event_count
  end

  def test_reading_and_recommending_do_not_infer_feedback
    session, recommendation = record_recommendation
    history_row = @history.list(session_id: session.fetch(:id), limit: 0).fetch(:rows).first
    _new_session, _another_recommendation = record_recommendation(title: 'Another Song')

    assert_empty history_row.fetch('feedback_events')
    assert_empty effective_rows(recommendation.fetch(:id))
    assert_equal 0, feedback_event_count
  end

  def test_feedback_selector_and_pagination_are_validated
    _session, recommendation = record_recommendation
    @feedback.add(recommendation_id: recommendation.fetch(:id), reaction: 'liked')

    missing_selector_error = assert_raises(Crackdealer::Error) do
      @feedback.effective_for
    end
    conflicting_selector_error = assert_raises(Crackdealer::Error) do
      @feedback.effective_for(recommendation_id: recommendation.fetch(:id), artist: 'New Artist', title: 'New Song')
    end
    invalid_limit_error = assert_raises(Crackdealer::Error) do
      @feedback.effective_for(artist: 'New Artist', title: 'New Song', limit: -1)
    end
    assert_equal 'invalid_input', missing_selector_error.code
    assert_equal 'invalid_input', conflicting_selector_error.code
    assert_equal 'invalid_input', invalid_limit_error.code
    assert_equal 1, @feedback.effective_for(recommendation_id: recommendation.fetch(:id), limit: 1).fetch(:rows).length
  end

  private

  def record_recommendation(artist: 'New Artist', title: 'New Song', album: nil, context_key: 'playlist:autumn-mix')
    session = @history.create_session(request: 'Find music for the autumn mix', context_key: context_key)
    recommendation = @history.add_recommendations(
      session_id: session.fetch(:id),
      recommendations: [recommendation_payload(artist: artist, title: title, album: album)]
    ).first
    [session, recommendation]
  end

  def recommendation_payload(artist:, title:, album: nil, library_track_key: nil)
    {
      artist: artist,
      title: title,
      album: album,
      library_track_key: library_track_key,
      reason: 'Fits the requested atmosphere'
    }
  end

  def effective_rows(recommendation_id)
    @feedback.effective_for(recommendation_id: recommendation_id, limit: 0).fetch(:rows)
  end

  def durable_counts
    @database.with_read do |connection|
      %w[sessions recommendations feedback_events].to_h do |table_name|
        [table_name, connection.get_first_value("SELECT COUNT(*) FROM #{table_name}").to_i]
      end
    end
  end

  def feedback_event_count
    durable_counts.fetch('feedback_events')
  end

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def find_library_track(track_key)
    @database.with_read do |connection|
      connection.get_first_row('SELECT track_key FROM tracks WHERE track_key = ?', [track_key])
    end
  end
end
