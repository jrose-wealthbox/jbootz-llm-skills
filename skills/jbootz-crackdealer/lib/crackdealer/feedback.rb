require 'securerandom'
require 'time'

module Crackdealer
  class Feedback
    DEFAULT_LIMIT = 50
    REACTIONS = %w[liked disliked already_known wrong_fit dont_recommend note].freeze
    SCOPES = %w[context track artist].freeze

    def initialize(database:, clock: -> { Time.now.utc })
      @database = database
      @clock = clock
    end

    def add(recommendation_id:, reaction:, scope: 'context', note: nil)
      validate_text!(recommendation_id, 'recommendation_id')
      unless REACTIONS.include?(reaction)
        raise invalid_input_error('reaction must be a supported feedback value.')
      end
      unless SCOPES.include?(scope)
        raise invalid_input_error('scope must be context, track, or artist.')
      end
      validate_optional_note!(note)
      if reaction == 'note' && (note.nil? || note.strip.empty?)
        raise invalid_input_error('The note reaction requires nonblank note text.')
      end

      @database.with_write do |connection|
        connection.transaction do
          recommendation = connection.get_first_row('SELECT id FROM recommendations WHERE id = ?', [recommendation_id])
          unless recommendation
            raise Error.new('Recommendation was not found.', code: 'not_found', exit_status: 2)
          end

          event = {
            id: SecureRandom.uuid,
            recommendation_id: recommendation_id,
            event_type: 'reaction',
            reaction: reaction,
            scope: scope,
            note: note,
            retracts_event_id: nil,
            created_at: timestamp
          }
          insert_event(connection, event)
          event
        end
      end
    end

    def retract(event_id:)
      validate_text!(event_id, 'event_id')
      @database.with_write do |connection|
        connection.transaction do
          event_to_retract = connection.get_first_row('SELECT * FROM feedback_events WHERE id = ?', [event_id])
          unless event_to_retract
            raise Error.new('Feedback event was not found.', code: 'not_found', exit_status: 2)
          end
          unless event_to_retract.fetch('event_type') == 'reaction'
            raise invalid_input_error('Only reaction events can be retracted.')
          end

          already_retracted = connection.get_first_value(
            'SELECT 1 FROM feedback_events WHERE retracts_event_id = ?', [event_id]
          )
          if already_retracted
            raise invalid_input_error('Feedback event has already been retracted.')
          end

          event = {
            id: SecureRandom.uuid,
            recommendation_id: event_to_retract.fetch('recommendation_id'),
            event_type: 'retraction',
            reaction: nil,
            scope: event_to_retract.fetch('scope'),
            note: nil,
            retracts_event_id: event_id,
            created_at: timestamp
          }
          insert_event(connection, event)
          event
        end
      end
    end

    def effective_for(recommendation_id: nil, artist: nil, title: nil, version_label: nil,
                      context_key: nil, limit: DEFAULT_LIMIT, offset: 0)
      validate_pagination!(limit, offset)
      target = resolve_target(
        recommendation_id: recommendation_id,
        artist: artist,
        title: title,
        version_label: version_label,
        context_key: context_key
      )

      @database.with_read do |connection|
        query_feedback(connection, target, limit, offset)
      end
    end

    private

    def resolve_target(recommendation_id:, artist:, title:, version_label:, context_key:)
      validate_optional_text!(context_key, 'context_key')
      if recommendation_id
        validate_text!(recommendation_id, 'recommendation_id')
        if artist || title || version_label
          raise invalid_input_error('Use recommendation_id or artist/title, not both.')
        end
        target = @database.with_read do |connection|
          connection.get_first_row(<<~SQL, [recommendation_id])
            SELECT r.artist_key, r.recording_key, s.context_key
            FROM recommendations r
            JOIN sessions s ON s.id = r.session_id
            WHERE r.id = ?
          SQL
        end
        unless target
          raise Error.new('Recommendation was not found.', code: 'not_found', exit_status: 2)
        end
        return {
          artist_key: target.fetch('artist_key'),
          recording_key: target.fetch('recording_key'),
          context_key: context_key || target.fetch('context_key')
        }
      end

      unless artist && title
        raise invalid_input_error('Provide recommendation_id or both artist and title.')
      end
      validate_text!(artist, 'artist')
      validate_text!(title, 'title')
      validate_optional_text!(version_label, 'version_label')
      {
        artist_key: Identity.normalize(artist),
        recording_key: Identity.recording_key(artist: artist, title: title, version_label: version_label),
        context_key: context_key
      }
    end

    def query_feedback(connection, target, limit, offset)
      context_sql = ''
      bindings = [target.fetch(:recording_key), target.fetch(:artist_key)]
      if target.fetch(:context_key)
        context_sql = <<~SQL
          OR (event.scope = 'context'
            AND recommendation.recording_key = ?
            AND origin_session.context_key = ?)
        SQL
        bindings << target.fetch(:recording_key)
        bindings << target.fetch(:context_key)
      end
      limit_sql = limit.zero? ? 'LIMIT -1' : 'LIMIT ?'
      pagination_bindings = limit.zero? ? [offset] : [limit + 1, offset]
      sql = <<~SQL
        SELECT event.*, origin_session.context_key AS origin_context_key,
          origin_session.request AS origin_request,
          recommendation.artist AS recommendation_artist,
          recommendation.title AS recommendation_title,
          recommendation.version_label AS recommendation_version_label,
          recommendation.session_id, recommendation.position AS recommendation_position
        FROM feedback_events event
        JOIN recommendations recommendation ON recommendation.id = event.recommendation_id
        JOIN sessions origin_session ON origin_session.id = recommendation.session_id
        WHERE event.event_type = 'reaction'
          AND NOT EXISTS (
            SELECT 1 FROM feedback_events retraction
            WHERE retraction.event_type = 'retraction'
              AND retraction.retracts_event_id = event.id
          )
          AND (
            (event.scope = 'track' AND recommendation.recording_key = ?)
            OR (event.scope = 'artist' AND recommendation.artist_key = ?)
            #{context_sql}
          )
        ORDER BY event.created_at DESC, event.id DESC
        #{limit_sql} OFFSET ?
      SQL
      selected_rows = connection.execute(sql, bindings + pagination_bindings)
      truncated = !limit.zero? && selected_rows.length > limit
      rows = limit.zero? ? selected_rows : selected_rows.first(limit)
      { rows: rows, truncated: truncated }
    end

    def insert_event(connection, event)
      connection.execute(
        <<~SQL,
          INSERT INTO feedback_events (
            id, recommendation_id, event_type, reaction, scope, note, retracts_event_id, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [
          event.fetch(:id), event.fetch(:recommendation_id), event.fetch(:event_type), event.fetch(:reaction),
          event.fetch(:scope), event.fetch(:note), event.fetch(:retracts_event_id), event.fetch(:created_at)
        ]
      )
    end

    def validate_pagination!(limit, offset)
      unless limit.is_a?(Integer) && limit >= 0 && offset.is_a?(Integer) && offset >= 0
        raise invalid_input_error('limit and offset must be nonnegative integers.')
      end
    end

    def validate_text!(value, label)
      unless value.is_a?(String) && !value.strip.empty?
        raise invalid_input_error("#{label} must be nonblank text.")
      end
    end

    def validate_optional_text!(value, label)
      return if value.nil?

      validate_text!(value, label)
    end

    def validate_optional_note!(note)
      return if note.nil?

      validate_text!(note, 'note')
    end

    def timestamp
      @clock.call.utc.iso8601(6)
    end

    def invalid_input_error(message)
      Error.new(message, code: 'invalid_input', exit_status: 2)
    end
  end
end
