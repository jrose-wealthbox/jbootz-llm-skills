require 'digest'
require 'json'

module Crackdealer
  class Importer
    def initialize(database:, clock: -> { Time.now.utc })
      @database = database
      @clock = clock
    end

    def import(path:, allow_empty: false)
      unless allow_empty == true || allow_empty == false
        raise invalid_import_input('allow_empty must be a boolean.')
      end

      started_at_s = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @database.initialize!
      snapshot = AppleLibrary.read(path)
      raise import_error('Apple Music export contains no tracks; pass --allow-empty to import it.') if snapshot.fetch(:tracks).empty? && !allow_empty

      mapped_snapshot = map_and_validate_snapshot(snapshot)
      imported_at = timestamp_for(@clock.call)
      source_sha256 = Digest::SHA256.file(File.expand_path(path)).hexdigest
      replace_snapshot(
        snapshot: mapped_snapshot,
        exported_at: snapshot.fetch(:exported_at),
        imported_at: imported_at,
        source_sha256: source_sha256
      )
      elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at_s
      {
        library_key: snapshot.fetch(:library_key),
        source_sha256: source_sha256,
        exported_at: snapshot.fetch(:exported_at),
        imported_at: imported_at,
        track_count: mapped_snapshot.fetch(:tracks).length,
        playlist_count: mapped_snapshot.fetch(:playlists).length,
        playlist_membership_count: mapped_snapshot.fetch(:playlist_tracks).length,
        unstable_track_key_count: mapped_snapshot.fetch(:unstable_track_key_count),
        unstable_playlist_key_count: mapped_snapshot.fetch(:unstable_playlist_key_count),
        field_counts: snapshot.fetch(:field_counts),
        warnings: snapshot.fetch(:warnings),
        warning_count: snapshot.fetch(:warnings).sum { |warning| warning.fetch(:count) },
        elapsed_s: elapsed_s
      }
    rescue Crackdealer::Error
      raise
    rescue SQLite3::Exception => error
      raise import_error('Apple Music snapshot could not be replaced.'), cause: error
    rescue SystemCallError, IOError => error
      raise Error.new('Apple Music export could not be read.', code: 'io_error'), cause: error
    end

    private

    def map_and_validate_snapshot(snapshot)
      library_key = snapshot.fetch(:library_key)
      existing_library_key = @database.with_read do |connection|
        connection.get_first_value('SELECT library_key FROM library_import WHERE id = 1')
      end
      if existing_library_key && existing_library_key != library_key
        raise import_error('This database belongs to a different Apple Music library.')
      end

      unstable_track_key_count = 0
      tracks = snapshot.fetch(:tracks).map do |track|
        source_track_id = track.fetch(:source_track_id)
        persistent_id = track.fetch(:persistent_id)
        if persistent_id.nil? || persistent_id.strip.empty?
          unless source_track_id.is_a?(Integer)
            raise import_error('A track without Persistent ID must have a numeric Track ID.')
          end
          unstable_track_key_count += 1
          track_key = "apple_music:#{library_key}:local:#{source_track_id}"
        else
          track_key = "apple_music:#{library_key}:#{persistent_id}"
        end

        rating_100 = track.fetch(:rating_100)
        unless rating_100.nil? || rating_100.between?(0, 100)
          raise import_error('Track Rating must be between 0 and 100.')
        end
        validate_nonnegative_integer(track.fetch(:duration_ms), 'Total Time')
        validate_nonnegative_integer(track.fetch(:play_count), 'Play Count')
        validate_nonnegative_integer(track.fetch(:skip_count), 'Skip Count')
        raw_fields_json = JSON.generate(track.fetch(:raw_fields))
        {
          track_key: track_key,
          source_track_id: source_track_id,
          persistent_id: persistent_id,
          title: track.fetch(:title),
          artist: track.fetch(:artist),
          album: track.fetch(:album),
          album_artist: track.fetch(:album_artist),
          genre: track.fetch(:genre),
          year: track.fetch(:year),
          duration_ms: track.fetch(:duration_ms),
          rating_100: rating_100,
          rating_computed: track.fetch(:rating_computed),
          loved: track.fetch(:loved),
          play_count: track.fetch(:play_count),
          skip_count: track.fetch(:skip_count),
          date_added_at: track.fetch(:date_added_at),
          last_played_at: track.fetch(:last_played_at),
          compilation: track.fetch(:compilation),
          is_music: track.fetch(:is_music),
          artist_normalized: Identity.normalize(track.fetch(:artist)),
          title_normalized: Identity.normalize(track.fetch(:title)),
          album_normalized: Identity.normalize(track.fetch(:album)),
          raw_fields_json: raw_fields_json
        }
      end
      validate_unique!(tracks, :track_key, 'Track Persistent ID')
      validate_unique_non_nil!(tracks, :source_track_id, 'Track ID')

      unstable_playlist_key_count = 0
      playlists = snapshot.fetch(:playlists).map do |playlist|
        source_playlist_index = playlist.fetch(:source_playlist_index)
        source_playlist_id = playlist.fetch(:source_playlist_id)
        persistent_id = playlist.fetch(:persistent_id)
        if persistent_id.nil? || persistent_id.strip.empty?
          unless source_playlist_id.is_a?(Integer)
            raise import_error('A playlist without Persistent ID must have a numeric Playlist ID.')
          end
          unstable_playlist_key_count += 1
          playlist_key = "apple_music:#{library_key}:local:#{source_playlist_id}"
        else
          playlist_key = "apple_music:#{library_key}:#{persistent_id}"
        end
        {
          source_playlist_index: source_playlist_index,
          playlist_key: playlist_key,
          source_playlist_id: source_playlist_id,
          persistent_id: persistent_id,
          name: playlist.fetch(:name),
          name_normalized: Identity.normalize(playlist.fetch(:name)),
          parent_persistent_id: playlist.fetch(:parent_persistent_id),
          kind: playlist.fetch(:kind),
          raw_fields_json: JSON.generate(playlist.fetch(:raw_fields))
        }
      end
      validate_unique!(playlists, :playlist_key, 'Playlist Persistent ID')
      validate_unique_non_nil!(playlists, :source_playlist_id, 'Playlist ID')

      track_keys_by_source_id = tracks.to_h { |track| [track.fetch(:source_track_id), track.fetch(:track_key)] }
      playlist_keys_by_source_index = playlists.to_h do |playlist|
        [playlist.fetch(:source_playlist_index), playlist.fetch(:playlist_key)]
      end
      playlist_tracks = snapshot.fetch(:playlist_tracks).filter_map do |membership|
        playlist_key = playlist_keys_by_source_index[membership.fetch(:source_playlist_index)]
        track_key = track_keys_by_source_id[membership.fetch(:source_track_id)]
        next if playlist_key.nil? || track_key.nil?

        position = membership.fetch(:position)
        raise import_error('Playlist membership position must be positive.') unless position.is_a?(Integer) && position.positive?

        { playlist_key: playlist_key, position: position, track_key: track_key }
      end
      validate_unique_membership_positions!(playlist_tracks)

      {
        library_key: library_key,
        tracks: tracks,
        playlists: playlists,
        playlist_tracks: playlist_tracks,
        unstable_track_key_count: unstable_track_key_count,
        unstable_playlist_key_count: unstable_playlist_key_count
      }
    end

    def replace_snapshot(snapshot:, exported_at:, imported_at:, source_sha256:)
      @database.with_write do |connection|
        connection.transaction do
          existing_library_key = connection.get_first_value('SELECT library_key FROM library_import WHERE id = 1')
          if existing_library_key && existing_library_key != snapshot.fetch(:library_key)
            raise import_error('This database belongs to a different Apple Music library.')
          end

          connection.execute('DELETE FROM playlist_tracks')
          connection.execute('DELETE FROM tracks')
          connection.execute('DELETE FROM playlists')
          insert_tracks(connection, snapshot.fetch(:tracks))
          insert_playlists(connection, snapshot.fetch(:playlists))
          insert_playlist_tracks(connection, snapshot.fetch(:playlist_tracks))
          upsert_import_record(
            connection,
            library_key: snapshot.fetch(:library_key),
            source_sha256: source_sha256,
            exported_at: exported_at,
            imported_at: imported_at,
            track_count: snapshot.fetch(:tracks).length,
            playlist_count: snapshot.fetch(:playlists).length
          )
        end
      end
    end

    def insert_tracks(connection, tracks)
      sql = <<~SQL
        INSERT INTO tracks (
          track_key, source_track_id, persistent_id, title, artist, album, album_artist, genre, year,
          duration_ms, rating_100, rating_computed, loved, play_count, skip_count, date_added_at,
          last_played_at, compilation, is_music, artist_normalized, title_normalized, album_normalized,
          raw_fields_json
        ) VALUES (#{(['?'] * 23).join(', ')})
      SQL
      tracks.each do |track|
        connection.execute(sql, [
          track.fetch(:track_key), track.fetch(:source_track_id), track.fetch(:persistent_id),
          track.fetch(:title), track.fetch(:artist), track.fetch(:album), track.fetch(:album_artist),
          track.fetch(:genre), track.fetch(:year), track.fetch(:duration_ms), track.fetch(:rating_100),
          track.fetch(:rating_computed), track.fetch(:loved), track.fetch(:play_count), track.fetch(:skip_count),
          track.fetch(:date_added_at), track.fetch(:last_played_at), track.fetch(:compilation),
          track.fetch(:is_music), track.fetch(:artist_normalized), track.fetch(:title_normalized),
          track.fetch(:album_normalized), track.fetch(:raw_fields_json)
        ])
      end
    end

    def insert_playlists(connection, playlists)
      sql = <<~SQL
        INSERT INTO playlists (
          playlist_key, source_playlist_id, persistent_id, name, name_normalized,
          parent_persistent_id, kind, raw_fields_json
        ) VALUES (#{(['?'] * 8).join(', ')})
      SQL
      playlists.each do |playlist|
        connection.execute(sql, [
          playlist.fetch(:playlist_key), playlist.fetch(:source_playlist_id), playlist.fetch(:persistent_id),
          playlist.fetch(:name), playlist.fetch(:name_normalized), playlist.fetch(:parent_persistent_id),
          playlist.fetch(:kind), playlist.fetch(:raw_fields_json)
        ])
      end
    end

    def insert_playlist_tracks(connection, memberships)
      memberships.each do |membership|
        connection.execute(
          'INSERT INTO playlist_tracks (playlist_key, position, track_key) VALUES (?, ?, ?)',
          [membership.fetch(:playlist_key), membership.fetch(:position), membership.fetch(:track_key)]
        )
      end
    end

    def upsert_import_record(connection, library_key:, source_sha256:, exported_at:, imported_at:, track_count:, playlist_count:)
      connection.execute(<<~SQL, [library_key, source_sha256, exported_at, imported_at, track_count, playlist_count])
        INSERT INTO library_import (
          id, source_kind, library_key, source_sha256, exported_at, imported_at, track_count, playlist_count
        ) VALUES (1, 'apple_music', ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          source_kind = excluded.source_kind,
          library_key = excluded.library_key,
          source_sha256 = excluded.source_sha256,
          exported_at = excluded.exported_at,
          imported_at = excluded.imported_at,
          track_count = excluded.track_count,
          playlist_count = excluded.playlist_count
      SQL
    end

    def validate_nonnegative_integer(value, field_name)
      return if value.nil? || (value.is_a?(Integer) && value >= 0)

      raise import_error("#{field_name} must be a nonnegative integer.")
    end

    def validate_unique!(rows, field_name, description)
      values = rows.map { |row| row.fetch(field_name) }
      raise import_error("Duplicate #{description} values are not supported.") unless values.uniq.length == values.length
    end

    def validate_unique_non_nil!(rows, field_name, description)
      values = rows.filter_map { |row| row.fetch(field_name) }
      raise import_error("Duplicate #{description} values are not supported.") unless values.uniq.length == values.length
    end

    def validate_unique_membership_positions!(memberships)
      keys = memberships.map { |membership| [membership.fetch(:playlist_key), membership.fetch(:position)] }
      raise import_error('Playlist membership positions are duplicated.') unless keys.uniq.length == keys.length
    end

    def timestamp_for(value)
      raise import_error('Import clock must return a Time.') unless value.is_a?(Time)

      value.utc.iso8601(6)
    end

    def import_error(message)
      Error.new(message, code: 'import_error')
    end

    def invalid_import_input(message)
      Error.new(message, code: 'invalid_input', exit_status: 2)
    end
  end
end
