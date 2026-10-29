require 'json'
require 'securerandom'
require 'uri'

module Crackdealer
  class History
    DEFAULT_LIMIT = 50
    LINK_SERVICES = %w[apple_music spotify youtube other].freeze

    def initialize(database:, clock: -> { Time.now.utc })
      @database = database
      @clock = clock
    end

    def create_session(request:, context_key: nil, context: {})
      validate_text!(request, 'request')
      validate_object!(context, 'context')
      id = SecureRandom.uuid
      selected_context_key = context_key.nil? ? "session:#{id}" : context_key
      validate_text!(selected_context_key, 'context_key')
      context_json = JSON.generate(context)
      created_at = timestamp

      @database.with_write do |connection|
        connection.transaction do
          connection.execute(
            'INSERT INTO sessions (id, request, context_key, context_json, created_at) VALUES (?, ?, ?, ?, ?)',
            [id, request, selected_context_key, context_json, created_at]
          )
        end
      end

      {
        id: id,
        request: request,
        context_key: selected_context_key,
        context: JSON.parse(context_json),
        created_at: created_at
      }
    rescue JSON::GeneratorError, TypeError => error
      raise invalid_input_error('Session context must contain JSON-compatible values.'), cause: error
    end

    def add_recommendations(session_id:, recommendations:)
      validate_text!(session_id, 'session_id')
      unless recommendations.is_a?(Array)
        raise invalid_input_error('recommendations must be an array.')
      end
      if recommendations.empty?
        raise invalid_input_error('recommendations must contain at least one selected track.')
      end

      @database.with_write do |connection|
        connection.transaction do
          session = connection.get_first_row('SELECT id FROM sessions WHERE id = ?', [session_id])
          raise Error.new('Recommendation session was not found.', code: 'not_found', exit_status: 2) unless session

          next_position = connection.get_first_value(
            'SELECT COALESCE(MAX(position), 0) + 1 FROM recommendations WHERE session_id = ?',
            [session_id]
          ).to_i
          recommendations.map do |payload|
            recommendation = validate_recommendation!(payload)
            validate_library_track!(connection, recommendation.fetch(:library_track_key))
            record = build_recommendation_record(session_id, next_position, recommendation)
            insert_recommendation(connection, record)
            next_position += 1
            record
          end
        end
      end
    rescue JSON::GeneratorError, TypeError => error
      raise invalid_input_error('Recommendation links must contain JSON-compatible values.'), cause: error
    end

    def list(session_id: nil, recording_key: nil, artist: nil, context_key: nil,
             limit: DEFAULT_LIMIT, offset: 0)
      validate_pagination!(limit, offset)
      filters = []
      bindings = []
      add_filter(filters, bindings, 'r.session_id = ?', session_id, 'session_id')
      add_filter(filters, bindings, 'r.recording_key = ?', recording_key, 'recording_key')
      add_filter(filters, bindings, 'r.artist_key = ?', Identity.normalize(artist), 'artist') if artist
      add_filter(filters, bindings, 's.context_key = ?', context_key, 'context_key')
      where_sql = filters.empty? ? '' : "WHERE #{filters.join(' AND ')}"
      limit_sql = limit.zero? ? 'LIMIT -1' : 'LIMIT ?'
      pagination_bindings = limit.zero? ? [offset] : [limit + 1, offset]
      sql = <<~SQL
        SELECT r.*, s.request AS session_request, s.context_key, s.context_json
        FROM recommendations r
        JOIN sessions s ON s.id = r.session_id
        #{where_sql}
        ORDER BY r.created_at DESC, r.session_id DESC, r.position DESC, r.id DESC
        #{limit_sql} OFFSET ?
      SQL

      @database.with_read do |connection|
        query_bindings = bindings + pagination_bindings
        selected_rows = connection.execute(sql, query_bindings).dup
        truncated = !limit.zero? && selected_rows.length > limit
        selected_rows.pop if truncated
        rows = selected_rows.map { |row| present_history_row(row) }
        attach_active_feedback(connection, rows)
        { rows: rows, truncated: truncated }
      end
    end

    def export
      @database.with_read do |connection|
        connection.transaction do
          {
            export_format_version: 1,
            sessions: connection.execute('SELECT * FROM sessions ORDER BY created_at, id'),
            recommendations: connection.execute(
              'SELECT * FROM recommendations ORDER BY session_id, position, id'
            ),
            feedback_events: connection.execute('SELECT * FROM feedback_events ORDER BY created_at, id')
          }
        end
      end
    end

    private

    def validate_recommendation!(payload)
      unless payload.is_a?(Hash)
        raise invalid_input_error('Each recommendation must be a JSON object.')
      end

      values = payload.each_with_object({}) { |(key, value), normalized| normalized[key.to_s] = value }
      allowed_keys = %w[artist title album version_label library_track_key reason links]
      unless (values.keys - allowed_keys).empty?
        raise invalid_input_error('Recommendation contains an unknown field.')
      end
      artist = values['artist']
      title = values['title']
      reason = values['reason']
      validate_text!(artist, 'artist')
      validate_text!(title, 'title')
      validate_text!(reason, 'reason')
      album = values['album']
      version_label = values['version_label']
      library_track_key = values['library_track_key']
      validate_optional_text!(album, 'album')
      validate_optional_text!(version_label, 'version_label')
      validate_optional_text!(library_track_key, 'library_track_key')
      links = validate_links!(values.fetch('links', []))

      {
        artist: artist,
        title: title,
        album: album,
        version_label: version_label,
        library_track_key: library_track_key,
        artist_key: Identity.normalize(artist),
        recording_key: Identity.recording_key(artist: artist, title: title, version_label: version_label),
        reason: reason,
        links: links
      }
    end

    def validate_links!(links)
      unless links.is_a?(Array)
        raise invalid_input_error('Recommendation links must be an array.')
      end

      links.map do |link|
        unless link.is_a?(Hash)
          raise invalid_input_error('Each recommendation link must be an object.')
        end
        link_values = link.each_with_object({}) { |(key, value), normalized| normalized[key.to_s] = value }
        unless (link_values.keys - %w[service url]).empty? && link_values.keys.sort == %w[service url]
          raise invalid_input_error('Each recommendation link must contain only service and url.')
        end
        service = link_values.fetch('service')
        url = link_values.fetch('url')
        unless LINK_SERVICES.include?(service) && url.is_a?(String)
          raise invalid_input_error('Recommendation links require a supported service and HTTP(S) URL.')
        end
        parsed_url = URI.parse(url)
        unless (parsed_url.is_a?(URI::HTTP) || parsed_url.is_a?(URI::HTTPS)) && parsed_url.host && !parsed_url.host.empty?
          raise invalid_input_error('Recommendation links require a supported service and HTTP(S) URL.')
        end
        { 'service' => service, 'url' => url }
      rescue URI::InvalidURIError
        raise invalid_input_error('Recommendation links require a supported service and HTTP(S) URL.')
      end
    end

    def validate_library_track!(connection, library_track_key)
      return if library_track_key.nil?

      exists = connection.get_first_value('SELECT 1 FROM tracks WHERE track_key = ?', [library_track_key])
      return if exists

      raise invalid_input_error('library_track_key must identify a track in the current library snapshot.')
    end

    def build_recommendation_record(session_id, position, recommendation)
      created_at = timestamp
      {
        id: SecureRandom.uuid,
        session_id: session_id,
        position: position,
        artist: recommendation.fetch(:artist),
        title: recommendation.fetch(:title),
        album: recommendation.fetch(:album),
        version_label: recommendation.fetch(:version_label),
        library_track_key: recommendation.fetch(:library_track_key),
        artist_key: recommendation.fetch(:artist_key),
        recording_key: recommendation.fetch(:recording_key),
        reason: recommendation.fetch(:reason),
        links: recommendation.fetch(:links),
        created_at: created_at
      }
    end

    def insert_recommendation(connection, record)
      bindings = [
        record.fetch(:id), record.fetch(:session_id), record.fetch(:position), record.fetch(:artist),
        record.fetch(:title), record.fetch(:album), record.fetch(:version_label), record.fetch(:library_track_key),
        record.fetch(:artist_key), record.fetch(:recording_key), record.fetch(:reason),
        JSON.generate(record.fetch(:links)), record.fetch(:created_at)
      ]
      connection.execute(<<~SQL, bindings)
        INSERT INTO recommendations (
          id, session_id, position, artist, title, album, version_label, library_track_key,
          artist_key, recording_key, reason, links_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      record
    end

    def present_history_row(row)
      row = row.dup
      row['links'] = JSON.parse(row.delete('links_json'))
      row['context'] = JSON.parse(row.delete('context_json'))
      row['request'] = row.delete('session_request')
      row['feedback_events'] = []
      row
    end

    def attach_active_feedback(connection, rows)
      return if rows.empty?

      recommendation_ids = rows.map { |row| row.fetch('id') }
      placeholders = Array.new(recommendation_ids.length, '?').join(', ')
      feedback_rows = connection.execute(<<~SQL, recommendation_ids)
        SELECT event.*
        FROM feedback_events event
        WHERE event.event_type = 'reaction'
          AND event.recommendation_id IN (#{placeholders})
          AND NOT EXISTS (
            SELECT 1 FROM feedback_events retraction
            WHERE retraction.event_type = 'retraction'
              AND retraction.retracts_event_id = event.id
          )
        ORDER BY event.created_at, event.id
      SQL
      feedback_by_recommendation = feedback_rows.group_by { |event| event.fetch('recommendation_id') }
      rows.each do |row|
        row['feedback_events'] = feedback_by_recommendation.fetch(row.fetch('id'), [])
      end
    end

    def add_filter(filters, bindings, sql, value, label)
      return if value.nil?

      validate_text!(value, label)
      filters << sql
      bindings << value
    end

    def validate_pagination!(limit, offset)
      unless limit.is_a?(Integer) && limit >= 0 && offset.is_a?(Integer) && offset >= 0
        raise invalid_input_error('limit and offset must be nonnegative integers.')
      end
    end

    def validate_object!(value, label)
      unless value.is_a?(Hash)
        raise invalid_input_error("#{label} must be a JSON object.")
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

    def timestamp
      @clock.call.utc.iso8601(6)
    end

    def invalid_input_error(message)
      Error.new(message, code: 'invalid_input', exit_status: 2)
    end
  end
end
