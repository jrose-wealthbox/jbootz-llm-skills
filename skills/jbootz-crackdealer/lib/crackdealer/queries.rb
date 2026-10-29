module Crackdealer
  class Queries
    SECONDS_PER_DAY = 86_400
    SIGNAL_FILTERS = {
      'positive' => '(explicit_positive = 1 OR loved_positive = 1 OR manual_playlist_count > 0 OR frequent_play = 1)',
      'negative' => 'explicit_negative = 1',
      'unexplored' => 'unexplored_candidate = 1',
      'rediscover' => 'rediscovery_candidate = 1'
    }.freeze
    TRACK_COLUMNS = %w[
      track_key source_track_id persistent_id title artist album album_artist genre year duration_ms
      rating_100 rating_computed loved play_count skip_count date_added_at last_played_at compilation
      is_music explicit_positive explicit_negative loved_positive manual_playlist_count frequent_play
      low_or_unknown_play stale_play unexplored_candidate rediscovery_candidate
    ].freeze
    TRACK_BOOLEAN_COLUMNS = %w[
      explicit_positive explicit_negative loved_positive frequent_play low_or_unknown_play stale_play
      unexplored_candidate rediscovery_candidate
    ].freeze
    PLAYLIST_COLUMNS = %w[
      playlist_key source_playlist_id persistent_id name name_normalized parent_persistent_id kind membership_count
    ].freeze
    MEMBERSHIP_COLUMNS = %w[
      playlist_key position track_key source_track_id persistent_id title artist album album_artist genre year
      duration_ms rating_100 rating_computed loved play_count skip_count date_added_at last_played_at compilation is_music
    ].freeze

    def initialize(database:, clock: -> { Time.now.utc })
      @database = database
      @clock = clock
    end

    def tracks(search: nil, artist: nil, playlist_key: nil, signal: nil, frequent_play_count: 10,
               low_play_count: 2, stale_days: 730, include_nonmusic: false, limit: 50, offset: 0)
      validate_pagination!(limit, offset)
      validate_thresholds!(frequent_play_count, low_play_count, stale_days)
      validate_signal!(signal)
      unless include_nonmusic == true || include_nonmusic == false
        raise invalid_input_error('include_nonmusic must be a boolean.')
      end

      conditions = []
      bindings = [frequent_play_count, low_play_count, stale_cutoff(stale_days)]
      conditions << 'is_music = 1' unless include_nonmusic
      signal_condition = SIGNAL_FILTERS[signal]
      conditions << signal_condition if signal_condition

      search_text = normalized_filter(search)
      unless search_text.empty?
        search_pattern = like_pattern(search_text)
        conditions << <<~SQL
          (title_normalized LIKE ? ESCAPE '!' OR artist_normalized LIKE ? ESCAPE '!' OR album_normalized LIKE ? ESCAPE '!')
        SQL
        bindings.concat([search_pattern, search_pattern, search_pattern])
      end

      artist_text = normalized_filter(artist)
      unless artist_text.empty?
        conditions << "artist_normalized LIKE ? ESCAPE '!'"
        bindings << like_pattern(artist_text)
      end

      if playlist_key
        conditions << 'EXISTS (SELECT 1 FROM playlist_tracks filter_membership WHERE filter_membership.track_key = evidence.track_key AND filter_membership.playlist_key = ?)'
        bindings << playlist_key
      end

      sql = <<~SQL
        WITH evidence_base AS (
          SELECT
            tracks.*,
            (
              SELECT COUNT(DISTINCT curated_playlist.playlist_key)
              FROM playlist_tracks curated_membership
              JOIN playlists curated_playlist ON curated_playlist.playlist_key = curated_membership.playlist_key
              WHERE curated_membership.track_key = tracks.track_key
                AND curated_playlist.kind = 'manual'
            ) AS manual_playlist_count,
            CASE WHEN rating_100 >= 80 AND COALESCE(rating_computed, 0) <> 1 THEN 1 ELSE 0 END AS explicit_positive,
            CASE WHEN rating_100 > 0 AND rating_100 <= 40 AND COALESCE(rating_computed, 0) <> 1 THEN 1 ELSE 0 END AS explicit_negative,
            CASE WHEN loved = 1 THEN 1 ELSE 0 END AS loved_positive,
            CASE WHEN play_count IS NOT NULL AND play_count >= ? THEN 1 ELSE 0 END AS frequent_play,
            CASE WHEN play_count IS NULL OR play_count <= ? THEN 1 ELSE 0 END AS low_or_unknown_play,
            CASE WHEN last_played_at IS NOT NULL AND last_played_at < ? THEN 1 ELSE 0 END AS stale_play
          FROM tracks
        ), evidence AS (
          SELECT
            evidence_base.*,
            CASE
              WHEN low_or_unknown_play = 1
                AND (rating_100 IS NULL OR rating_100 = 0 OR rating_computed = 1)
                AND COALESCE(loved, 0) = 0
                AND manual_playlist_count = 0
              THEN 1 ELSE 0
            END AS unexplored_candidate,
            CASE
              WHEN stale_play = 1
                AND (explicit_positive = 1 OR loved_positive = 1 OR manual_playlist_count > 0 OR frequent_play = 1)
              THEN 1 ELSE 0
            END AS rediscovery_candidate
          FROM evidence_base
        )
        SELECT #{TRACK_COLUMNS.join(', ')}
        FROM evidence
        #{'WHERE ' + conditions.join(' AND ') unless conditions.empty?}
        ORDER BY artist_normalized, title_normalized, track_key
      SQL

      @database.with_read do |connection|
        connection.results_as_hash = false
        if playlist_key && connection.get_first_value('SELECT 1 FROM playlists WHERE playlist_key = ?', playlist_key).nil?
          raise not_found_error("Playlist key was not found.")
        end
        execute_page(connection, sql, bindings, TRACK_COLUMNS, TRACK_BOOLEAN_COLUMNS, limit, offset)
      end
    end

    def playlists(search: nil, limit: 50, offset: 0)
      validate_pagination!(limit, offset)
      conditions = []
      bindings = []
      search_text = normalized_filter(search)
      unless search_text.empty?
        conditions << "name_normalized LIKE ? ESCAPE '!'"
        bindings << like_pattern(search_text)
      end

      sql = <<~SQL
        SELECT
          playlists.playlist_key,
          playlists.source_playlist_id,
          playlists.persistent_id,
          playlists.name,
          playlists.name_normalized,
          playlists.parent_persistent_id,
          playlists.kind,
          (SELECT COUNT(*) FROM playlist_tracks WHERE playlist_tracks.playlist_key = playlists.playlist_key) AS membership_count
        FROM playlists
        #{'WHERE ' + conditions.join(' AND ') unless conditions.empty?}
        ORDER BY name_normalized, playlist_key
      SQL
      @database.with_read do |connection|
        connection.results_as_hash = false
        execute_page(connection, sql, bindings, PLAYLIST_COLUMNS, [], limit, offset)
      end
    end

    def playlist(playlist_key:, limit: 50, offset: 0)
      validate_pagination!(limit, offset)
      sql = <<~SQL
        SELECT
          playlist_tracks.playlist_key,
          playlist_tracks.position,
          tracks.track_key,
          tracks.source_track_id,
          tracks.persistent_id,
          tracks.title,
          tracks.artist,
          tracks.album,
          tracks.album_artist,
          tracks.genre,
          tracks.year,
          tracks.duration_ms,
          tracks.rating_100,
          tracks.rating_computed,
          tracks.loved,
          tracks.play_count,
          tracks.skip_count,
          tracks.date_added_at,
          tracks.last_played_at,
          tracks.compilation,
          tracks.is_music
        FROM playlist_tracks
        JOIN tracks ON tracks.track_key = playlist_tracks.track_key
        WHERE playlist_tracks.playlist_key = ?
        ORDER BY playlist_tracks.position
      SQL
      @database.with_read do |connection|
        connection.results_as_hash = false
        if connection.get_first_value('SELECT 1 FROM playlists WHERE playlist_key = ?', playlist_key).nil?
          raise not_found_error('Playlist key was not found.')
        end
        execute_page(connection, sql, [playlist_key], MEMBERSHIP_COLUMNS, [], limit, offset)
      end
    end

    private

    def execute_page(connection, sql, bindings, output_columns, boolean_columns, limit, offset)
      pagination_sql, pagination_bindings = pagination_clause(limit, offset)
      database_rows = connection.execute("#{sql}#{pagination_sql}", bindings + pagination_bindings)
      rows = database_rows.map do |database_row|
        row_hash = output_columns.zip(database_row).to_h
        boolean_columns.each { |column_name| row_hash[column_name] = row_hash[column_name] == 1 }
        row_hash
      end
      truncated = limit.positive? && rows.length > limit
      rows = rows.first(limit) if truncated
      { rows: rows, truncated: truncated }
    end

    def pagination_clause(limit, offset)
      if limit.zero?
        [' LIMIT -1 OFFSET ?', [offset]]
      else
        [' LIMIT ? OFFSET ?', [limit + 1, offset]]
      end
    end

    def stale_cutoff(stale_days)
      clock_time = @clock.call
      unless clock_time.is_a?(Time)
        raise invalid_input_error('Query clock must return a Time.')
      end

      (clock_time.utc - stale_days * SECONDS_PER_DAY).iso8601(6)
    end

    def normalized_filter(value)
      return '' if value.nil?
      unless value.is_a?(String)
        raise invalid_input_error('Search filters must be strings.')
      end

      Identity.normalize(value)
    end

    def like_pattern(value)
      escaped_value = value.gsub(/[!%_]/) { |character| "!#{character}" }
      "%#{escaped_value}%"
    end

    def validate_pagination!(limit, offset)
      unless limit.is_a?(Integer) && limit >= 0 && offset.is_a?(Integer) && offset >= 0
        raise invalid_input_error('limit and offset must be nonnegative integers.')
      end
    end

    def validate_thresholds!(frequent_play_count, low_play_count, stale_days)
      unless frequent_play_count.is_a?(Integer) && frequent_play_count >= 1
        raise invalid_input_error('frequent_play_count must be an integer of at least 1.')
      end
      unless low_play_count.is_a?(Integer) && low_play_count >= 0
        raise invalid_input_error('low_play_count must be a nonnegative integer.')
      end
      unless stale_days.is_a?(Integer) && stale_days >= 0
        raise invalid_input_error('stale_days must be a nonnegative integer.')
      end
    end

    def validate_signal!(signal)
      return if signal.nil? || SIGNAL_FILTERS.key?(signal)

      raise invalid_input_error('signal must be positive, negative, unexplored, or rediscover.')
    end

    def invalid_input_error(message)
      Error.new(message, code: 'invalid_input', exit_status: 2)
    end

    def not_found_error(message)
      Error.new(message, code: 'not_found', exit_status: 2)
    end
  end
end
