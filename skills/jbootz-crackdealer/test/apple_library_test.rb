require_relative 'test_helper'

class AppleLibraryTest < CrackdealerTest
  def test_maps_plist_types_and_preserves_raw_fields
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))
    track = track_by_source_id(snapshot, 1)

    assert_equal 'AAAAAAAAAAAAAAAA', snapshot.fetch(:library_key)
    assert_equal '2026-10-23T12:00:00.000000Z', snapshot.fetch(:exported_at)
    assert_equal 10, snapshot.fetch(:tracks).length
    assert_equal 'Old Favorite', track.fetch(:title)
    assert_equal 180_000, track.fetch(:duration_ms)
    assert_equal 3.5, track.fetch(:raw_fields).fetch('Sample Real')
    assert_equal 'AAECAw==', track.fetch(:raw_fields).fetch('Sample Data')
    assert_equal false, track.fetch(:raw_fields).fetch('Sample False')
    assert_equal '2010-01-02T03:04:05.000000Z', track.fetch(:date_added_at)
  end

  def test_missing_zero_and_false_remain_distinct
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))
    favorite = track_by_source_id(snapshot, 1)
    unheard = track_by_source_id(snapshot, 2)
    missing_date = track_by_source_id(snapshot, 7)

    assert_nil favorite.fetch(:rating_computed)
    assert_nil favorite.fetch(:loved)
    assert_nil unheard.fetch(:rating_100)
    assert_equal 0, unheard.fetch(:loved)
    assert_equal 0, unheard.fetch(:play_count)
    assert_equal 0, missing_date.fetch(:rating_100)
    assert_equal 0, missing_date.fetch(:loved)
    assert_nil missing_date.fetch(:last_played_at)
  end

  def test_computed_and_album_ratings_are_not_explicit_track_ratings
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))
    computed_track = track_by_source_id(snapshot, 5)
    album_only_track = track_by_source_id(snapshot, 2)

    assert_equal 100, computed_track.fetch(:rating_100)
    assert_equal 1, computed_track.fetch(:rating_computed)
    assert_nil album_only_track.fetch(:rating_100)
    assert_equal 100, album_only_track.fetch(:raw_fields).fetch('Album Rating')
  end

  def test_playlist_classification_and_duplicate_positions
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))
    playlist_by_id = snapshot.fetch(:playlists).to_h { |playlist| [playlist.fetch(:source_playlist_id), playlist] }
    manual_playlists = snapshot.fetch(:playlists).select { |playlist| playlist.fetch(:kind) == 'manual' }
    first_manual_id = manual_playlists.find { |playlist| playlist.fetch(:source_playlist_id) == 1 }.fetch(:source_playlist_id)

    assert_equal 2, manual_playlists.count { |playlist| playlist.fetch(:name) == 'Shared & Name' }
    assert_equal 'smart', playlist_by_id.fetch(3).fetch(:kind)
    assert_equal 'folder', playlist_by_id.fetch(4).fetch(:kind)
    assert_equal 'system', playlist_by_id.fetch(5).fetch(:kind)
    first_memberships = snapshot.fetch(:playlist_tracks).select do |membership|
      membership.fetch(:source_playlist_id) == first_manual_id
    end
    assert_equal [1, 2, 4], first_memberships.map { |membership| membership.fetch(:position) }
    assert_equal [1, 1, 6], first_memberships.map { |membership| membership.fetch(:source_track_id) }
  end

  def test_reads_apple_playlist_persistent_id_field
    xml = File.read(fixture_path('library.xml'))
    xml.sub!(%r{(<key>Playlists</key>.*\z)}m) do |playlist_section|
      playlist_section.gsub('<key>Persistent ID</key>', '<key>Playlist Persistent ID</key>')
    end
    xml_path = write_xml('playlist-persistent-ids.xml', xml)

    snapshot = Crackdealer::AppleLibrary.read(xml_path)

    assert_equal 5, snapshot.fetch(:playlists).length
    assert_equal %w[1111111111111111 2222222222222222 3333333333333333 4444444444444444 5555555555555555],
      snapshot.fetch(:playlists).map { |playlist| playlist.fetch(:persistent_id) }
  end

  def test_dangling_playlist_items_are_reported
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))
    warning = snapshot.fetch(:warnings).find { |item| item.fetch(:code) == 'dangling_playlist_track' }

    refute_nil warning
    assert_equal 1, warning.fetch(:count)
    assert_equal 3, warning.fetch(:examples).first.fetch(:position)
  end

  def test_normal_xml_entities_and_non_ascii_names_are_decoded
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    snapshot = Crackdealer::AppleLibrary.read(fixture_path('library.xml'))

    assert_equal 'Explicit Reject & Leave', track_by_source_id(snapshot, 3).fetch(:title)
    assert_equal 'Björk', track_by_source_id(snapshot, 5).fetch(:artist)
  end

  def test_custom_entity_declarations_are_rejected_without_expansion
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    sentinel_path = File.join(@temporary_directory, 'sentinel.txt')
    File.write(sentinel_path, 'private sentinel content')
    xml_path = File.join(@temporary_directory, 'custom-entity.xml')
    File.write(xml_path, <<~XML)
      <?xml version="1.0"?>
      <!DOCTYPE plist [<!ENTITY local SYSTEM "file://#{sentinel_path}">]>
      <plist version="1.0"><dict><key>Library Persistent ID</key><string>AAAAAAAAAAAAAAAA</string><key>Tracks</key><dict><key>1</key><dict><key>Name</key><string>&local;</string></dict></dict></dict></plist>
    XML

    error = assert_raises(Crackdealer::Error) { Crackdealer::AppleLibrary.read(xml_path) }

    assert_equal 'import_error', error.code
    refute_includes error.message, 'private sentinel content'
  end

  def test_custom_entity_declarations_are_rejected_in_utf16_xml
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-16"?>
      <!DOCTYPE plist [<!ENTITY label "expanded custom entity">]>
      <plist version="1.0"><dict>
        <key>Library Persistent ID</key><string>AAAAAAAAAAAAAAAA</string>
        <key>Tracks</key><dict><key>1</key><dict>
          <key>Name</key><string>&label;</string>
        </dict></dict>
      </dict></plist>
    XML
    xml_path = File.join(@temporary_directory, 'custom-entity-utf16.xml')
    File.binwrite(xml_path, "\uFEFF".encode(Encoding::UTF_16LE) + xml.encode(Encoding::UTF_16LE))

    error = assert_raises(Crackdealer::Error) { Crackdealer::AppleLibrary.read(xml_path) }

    assert_equal 'import_error', error.code
    refute_includes error.message, 'expanded custom entity'
  end

  def test_duplicate_dictionary_keys_are_rejected
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    xml_path = write_xml('duplicate-keys.xml', <<~XML)
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>Library Persistent ID</key><string>AAAAAAAAAAAAAAAA</string>
        <key>Tracks</key><dict/>
        <key>Tracks</key><dict/>
      </dict></plist>
    XML

    error = assert_raises(Crackdealer::Error) { Crackdealer::AppleLibrary.read(xml_path) }

    assert_equal 'import_error', error.code
  end

  def test_malformed_dates_and_numbers_are_rejected
    assert_equal 'constant', defined?(Crackdealer::AppleLibrary), 'Apple plist reader is not loaded yet'
    xml = File.read(fixture_path('library.xml')).sub('<integer>180000</integer>', '<integer>not-a-number</integer>')
    xml_path = write_xml('bad-number.xml', xml)

    error = assert_raises(Crackdealer::Error) { Crackdealer::AppleLibrary.read(xml_path) }

    assert_equal 'import_error', error.code
  end

  private

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def track_by_source_id(snapshot, source_track_id)
    snapshot.fetch(:tracks).find { |track| track.fetch(:source_track_id) == source_track_id }
  end

  def write_xml(name, content)
    xml_path = File.join(@temporary_directory, name)
    File.write(xml_path, content)
    xml_path
  end
end
