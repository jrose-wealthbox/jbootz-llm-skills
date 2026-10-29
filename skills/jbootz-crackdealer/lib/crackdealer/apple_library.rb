require 'base64'
require 'set'
require 'time'
require 'nokogiri'

module Crackdealer
  class AppleLibrary
    TRACK_FIELDS = [
      'Track ID', 'Persistent ID', 'Name', 'Artist', 'Album', 'Album Artist', 'Genre', 'Year',
      'Total Time', 'Rating', 'Rating Computed', 'Loved', 'Play Count', 'Skip Count',
      'Date Added', 'Play Date UTC', 'Compilation'
    ].freeze
    NON_MUSIC_FLAGS = ['Podcast', 'Movie', 'TV Show', 'Music Video'].freeze
    ENTITY_SCAN_CHUNK_BYTES = 64 * 1024
    ENTITY_DECLARATION_MARKERS = [
      '<!ENTITY'.b,
      *[Encoding::UTF_16LE, Encoding::UTF_16BE, Encoding::UTF_32LE, Encoding::UTF_32BE].map do |encoding|
        '<!ENTITY'.encode(encoding).b
      end
    ].freeze
    ENTITY_SCAN_OVERLAP_BYTES = ENTITY_DECLARATION_MARKERS.map(&:bytesize).max - 1

    def self.read(path)
      unless path.is_a?(String) && !path.strip.empty?
        raise Error.new('Apple Music export path must be a nonblank file path.', code: 'invalid_input', exit_status: 2)
      end

      source_path = File.expand_path(path)
      raise Error.new('Apple Music export file does not exist.', code: 'io_error') unless File.file?(source_path)

      reject_custom_entity_declarations!(source_path)
      document = File.open(source_path, 'rb') do |xml_input|
        Nokogiri::XML::Document.parse(xml_input) do |parser_options|
          parser_options.strict.nonet
        end
      end
      root = document.root
      unless root&.name == 'plist'
        raise import_error('XML root must be a plist document.')
      end

      root_value = root.element_children.first
      unless root_value&.name == 'dict'
        raise import_error('Apple Music plist must contain a root dictionary.')
      end

      library_fields = parse_plist_value(root_value)
      library_key = nonblank_string(library_fields['Library Persistent ID'])
      raise import_error('Apple Music export is missing Library Persistent ID.') unless library_key

      raw_tracks = library_fields['Tracks']
      unless raw_tracks.is_a?(Hash)
        raise import_error('Apple Music export is missing a Tracks dictionary.')
      end
      raw_playlists = library_fields.fetch('Playlists', [])
      unless raw_playlists.is_a?(Array)
        raise import_error('Apple Music Playlists must be an array.')
      end

      tracks = raw_tracks.map do |dictionary_key, track_fields|
        map_track(dictionary_key, track_fields)
      end
      track_source_ids = tracks.filter_map { |track| track.fetch(:source_track_id) }.to_set
      playlists = raw_playlists.each_with_index.map do |playlist_fields, source_playlist_index|
        map_playlist(playlist_fields).merge(source_playlist_index: source_playlist_index)
      end
      playlist_tracks, warnings = map_playlist_tracks(playlists, track_source_ids)

      {
        library_key: library_key,
        exported_at: optional_string(library_fields['Date'], 'Date'),
        tracks: tracks,
        playlists: playlists,
        playlist_tracks: playlist_tracks,
        warnings: warnings,
        field_counts: field_counts(tracks)
      }
    rescue Crackdealer::Error
      raise
    rescue Nokogiri::XML::SyntaxError, ArgumentError, TypeError, KeyError => error
      raise import_error('Apple Music XML is malformed or contains unsupported plist values.'), cause: error
    rescue SystemCallError, IOError => error
      raise Error.new('Apple Music export could not be read.', code: 'io_error'), cause: error
    end

    def self.parse_plist_value(node)
      case node.name
      when 'dict'
        parse_dictionary(node)
      when 'array'
        node.element_children.map { |child| parse_plist_value(child) }
      when 'string'
        node.text
      when 'integer'
        parse_integer(node.text)
      when 'real'
        parse_real(node.text)
      when 'date'
        Time.iso8601(node.text.strip).utc.iso8601(6)
      when 'data'
        parse_data(node.text)
      when 'true'
        true
      when 'false'
        false
      else
        raise import_error("Unsupported plist value type: #{node.name}.")
      end
    end
    private_class_method :parse_plist_value

    def self.parse_dictionary(node)
      children = node.element_children
      unless children.length.even?
        raise import_error('Plist dictionary has an unmatched key or value.')
      end

      dictionary = {}
      children.each_slice(2) do |key_node, value_node|
        unless key_node.name == 'key'
          raise import_error('Plist dictionary entry does not begin with a key.')
        end

        key = key_node.text
        raise import_error('Plist dictionary contains a duplicate key.') if dictionary.key?(key)

        dictionary[key] = parse_plist_value(value_node)
      end
      dictionary
    end
    private_class_method :parse_dictionary

    def self.parse_integer(value)
      text = value.strip
      raise import_error('Plist integer value is malformed.') unless text.match?(/\A[+-]?\d+\z/)

      Integer(text, 10)
    end
    private_class_method :parse_integer

    def self.parse_real(value)
      number = Float(value.strip)
      raise import_error('Plist real value must be finite.') unless number.finite?

      number
    rescue ArgumentError
      raise import_error('Plist real value is malformed.')
    end
    private_class_method :parse_real

    def self.parse_data(value)
      compact_base64 = value.gsub(/\s+/, '')
      Base64.strict_encode64(Base64.strict_decode64(compact_base64))
    rescue ArgumentError
      raise import_error('Plist data value is malformed.')
    end
    private_class_method :parse_data

    def self.map_track(dictionary_key, fields)
      raise import_error('Track entry must be a plist dictionary.') unless fields.is_a?(Hash)

      dictionary_track_id = parse_dictionary_id(dictionary_key)
      source_track_id = integer_field(fields, 'Track ID') || dictionary_track_id
      persistent_id = optional_string(fields['Persistent ID'], 'Persistent ID')
      non_music = NON_MUSIC_FLAGS.any? { |field_name| boolean_field(fields, field_name) == true }
      {
        source_track_id: source_track_id,
        persistent_id: persistent_id,
        title: optional_string(fields['Name'], 'Name'),
        artist: optional_string(fields['Artist'], 'Artist'),
        album: optional_string(fields['Album'], 'Album'),
        album_artist: optional_string(fields['Album Artist'], 'Album Artist'),
        genre: optional_string(fields['Genre'], 'Genre'),
        year: integer_field(fields, 'Year'),
        duration_ms: integer_field(fields, 'Total Time'),
        rating_100: integer_field(fields, 'Rating'),
        rating_computed: boolean_to_integer(boolean_field(fields, 'Rating Computed')),
        loved: boolean_to_integer(boolean_field(fields, 'Loved')),
        play_count: integer_field(fields, 'Play Count'),
        skip_count: integer_field(fields, 'Skip Count'),
        date_added_at: optional_string(fields['Date Added'], 'Date Added'),
        last_played_at: optional_string(fields['Play Date UTC'], 'Play Date UTC'),
        compilation: boolean_to_integer(boolean_field(fields, 'Compilation')),
        is_music: non_music ? 0 : 1,
        raw_fields: fields
      }
    end
    private_class_method :map_track

    def self.map_playlist(fields)
      raise import_error('Playlist entry must be a plist dictionary.') unless fields.is_a?(Hash)

      persistent_id_key = fields.key?('Playlist Persistent ID') ? 'Playlist Persistent ID' : 'Persistent ID'
      {
        source_playlist_id: integer_field(fields, 'Playlist ID'),
        persistent_id: optional_string(fields[persistent_id_key], persistent_id_key),
        name: optional_string(fields['Name'], 'Name'),
        parent_persistent_id: optional_string(fields['Parent Persistent ID'], 'Parent Persistent ID'),
        kind: playlist_kind(fields),
        item_source_track_ids: playlist_item_ids(fields),
        raw_fields: fields
      }
    end
    private_class_method :map_playlist

    def self.playlist_kind(fields)
      return 'folder' if boolean_field(fields, 'Folder') == true
      return 'system' if boolean_field(fields, 'Master') == true || fields.key?('Distinguished Kind')
      return 'smart' if fields.key?('Smart Info') || fields.key?('Smart Criteria')

      'manual'
    end
    private_class_method :playlist_kind

    def self.playlist_item_ids(fields)
      items = fields.fetch('Playlist Items', [])
      raise import_error('Playlist Items must be an array.') unless items.is_a?(Array)

      items.map do |item|
        unless item.is_a?(Hash)
          raise import_error('Playlist item must be a plist dictionary.')
        end

        integer_field(item, 'Track ID')
      end
    end
    private_class_method :playlist_item_ids

    def self.map_playlist_tracks(playlists, track_source_ids)
      memberships = []
      dangling_examples = []
      dangling_count = 0
      playlists.each do |playlist|
        playlist.fetch(:item_source_track_ids).each_with_index do |source_track_id, item_index|
          position = item_index + 1
          if source_track_id.nil? || !track_source_ids.include?(source_track_id)
            dangling_count += 1
            if dangling_examples.length < 10
              dangling_examples << {
                source_playlist_id: playlist.fetch(:source_playlist_id),
                position: position,
                source_track_id: source_track_id
              }
            end
            next
          end

          memberships << {
            source_playlist_index: playlist.fetch(:source_playlist_index),
            source_playlist_id: playlist.fetch(:source_playlist_id),
            position: position,
            source_track_id: source_track_id
          }
        end
      end
      warnings = if dangling_count.positive?
        [{ code: 'dangling_playlist_track', count: dangling_count, examples: dangling_examples }]
      else
        []
      end
      [memberships, warnings]
    end
    private_class_method :map_playlist_tracks

    def self.field_counts(tracks)
      TRACK_FIELDS.to_h do |field_name|
        present_count = tracks.count { |track| track.fetch(:raw_fields).key?(field_name) }
        [field_name, { present_count: present_count, missing_count: tracks.length - present_count }]
      end
    end
    private_class_method :field_counts

    def self.integer_field(fields, field_name)
      value = fields[field_name]
      return nil if value.nil?
      return value if value.is_a?(Integer)

      raise import_error("Plist field #{field_name} must be an integer.")
    end
    private_class_method :integer_field

    def self.boolean_field(fields, field_name)
      value = fields[field_name]
      return nil if value.nil?
      return value if value == true || value == false

      raise import_error("Plist field #{field_name} must be a boolean.")
    end
    private_class_method :boolean_field

    def self.boolean_to_integer(value)
      return nil if value.nil?

      value ? 1 : 0
    end
    private_class_method :boolean_to_integer

    def self.optional_string(value, field_name)
      return nil if value.nil?
      return value if value.is_a?(String)

      raise import_error("Plist field #{field_name} must be a string.")
    end
    private_class_method :optional_string

    def self.nonblank_string(value)
      return nil unless value.is_a?(String)

      value unless value.strip.empty?
    end
    private_class_method :nonblank_string

    def self.parse_dictionary_id(value)
      return nil unless value.match?(/\A\d+\z/)

      Integer(value, 10)
    end
    private_class_method :parse_dictionary_id

    def self.reject_custom_entity_declarations!(source_path)
      overlap = +''
      File.open(source_path, 'rb') do |xml_input|
        while (chunk = xml_input.read(ENTITY_SCAN_CHUNK_BYTES))
          searchable_text = overlap + chunk
          if ENTITY_DECLARATION_MARKERS.any? { |marker| searchable_text.include?(marker) }
            raise import_error('Custom XML entity declarations are not supported.')
          end
          overlap = searchable_text.byteslice(-ENTITY_SCAN_OVERLAP_BYTES, ENTITY_SCAN_OVERLAP_BYTES) || searchable_text
        end
      end
    end
    private_class_method :reject_custom_entity_declarations!

    def self.import_error(message)
      Error.new(message, code: 'import_error')
    end
    private_class_method :import_error
  end
end
