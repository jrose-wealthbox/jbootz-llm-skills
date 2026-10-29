require_relative 'test_helper'
require 'time'

class ImporterTest < CrackdealerTest
  IMPORT_TIME = Time.iso8601('2026-10-23T12:00:00Z').freeze

  def setup
    super
    assert_equal 'constant', defined?(Crackdealer::Importer), 'importer implementation is not loaded yet'
    @database = build_database
    @importer = Crackdealer::Importer.new(database: @database, clock: -> { IMPORT_TIME })
  end

  def test_keys_survive_changed_numeric_ids
    first_report = @importer.import(path: fixture_path('library.xml'))
    track_key_before_refresh = find_track_key(source_track_id: 1)
    playlist_key_before_refresh = find_playlist_key(source_playlist_id: 1)

    updated_report = @importer.import(path: fixture_path('library_updated.xml'))

    assert_equal first_report.fetch(:library_key), updated_report.fetch(:library_key)
    assert_equal track_key_before_refresh, find_track_key(source_track_id: 101)
    assert_equal playlist_key_before_refresh, find_playlist_key(source_playlist_id: 1001)
  end

  def test_reimport_replaces_snapshot_without_duplicate_rows
    @importer.import(path: fixture_path('library.xml'))

    report = @importer.import(path: fixture_path('library_updated.xml'))

    assert_equal 9, report.fetch(:track_count)
    assert_equal 5, report.fetch(:playlist_count)
    assert_equal 9, count_rows('tracks')
    assert_equal 80, find_track(source_track_id: 101).fetch('rating_100')
    assert_nil find_track(source_track_id: 3)
  end

  def test_invalid_import_rolls_back
    @importer.import(path: fixture_path('library.xml'))
    snapshot_before_import = import_record
    invalid_path = File.join(@temporary_directory, 'malformed.xml')
    File.write(invalid_path, '<plist><dict>')

    error = assert_raises(Crackdealer::Error) { @importer.import(path: invalid_path) }

    assert_equal 'import_error', error.code
    assert_equal snapshot_before_import, import_record
    assert_equal 10, count_rows('tracks')
    assert_equal 1, find_track(source_track_id: 1).fetch('source_track_id')
  end

  def test_constraint_failure_after_replacement_starts_rolls_back
    @importer.import(path: fixture_path('library.xml'))
    snapshot_before_import = import_record
    @database.with_write do |connection|
      connection.execute_batch(<<~SQL)
        CREATE TRIGGER reject_updated_track
        BEFORE INSERT ON tracks
        WHEN NEW.source_track_id = 101
        BEGIN
          SELECT RAISE(ABORT, 'forced constraint failure');
        END;
      SQL
    end

    error = assert_raises(Crackdealer::Error) do
      @importer.import(path: fixture_path('library_updated.xml'))
    end

    assert_equal 'import_error', error.code
    assert_equal snapshot_before_import, import_record
    assert_equal 10, count_rows('tracks')
    assert_equal 1, find_track(source_track_id: 1).fetch('source_track_id')
  end

  def test_empty_import_requires_opt_in
    empty_path = write_empty_library

    error = assert_raises(Crackdealer::Error) { @importer.import(path: empty_path) }

    assert_equal 'import_error', error.code
    assert_equal 0, count_rows('library_import')
    report = @importer.import(path: empty_path, allow_empty: true)
    assert_equal 0, report.fetch(:track_count)
    assert_equal 0, count_rows('tracks')
  end

  def test_different_library_is_rejected
    @importer.import(path: fixture_path('library.xml'))
    different_library_xml = File.read(fixture_path('library_updated.xml')).sub(
      '<string>AAAAAAAAAAAAAAAA</string>',
      '<string>BBBBBBBBBBBBBBBB</string>'
    )
    different_library_path = write_xml('different-library.xml', different_library_xml)

    error = assert_raises(Crackdealer::Error) { @importer.import(path: different_library_path) }

    assert_equal 'import_error', error.code
    assert_equal 'AAAAAAAAAAAAAAAA', import_record.fetch('library_key')
    assert_equal 10, count_rows('tracks')
  end

  def test_missing_persistent_ids_report_unstable_keys
    fixture_xml = File.read(fixture_path('library.xml'))
    fixture_xml.sub!(%r{<key>Persistent ID</key>\s*<string>0000000000000001</string>}, '')
    fixture_xml.sub!(%r{<key>Persistent ID</key>\s*<string>1111111111111111</string>}, '')
    variant_path = write_xml('unstable-keys.xml', fixture_xml)

    report = @importer.import(path: variant_path)

    assert_equal 1, report.fetch(:unstable_track_key_count)
    assert_equal 1, report.fetch(:unstable_playlist_key_count)
    assert_equal 'apple_music:AAAAAAAAAAAAAAAA:local:1', find_track(source_track_id: 1).fetch('track_key')
    assert_equal 'apple_music:AAAAAAAAAAAAAAAA:local:1', find_playlist(source_playlist_id: 1).fetch('playlist_key')
  end

  def test_missing_numeric_playlist_ids_do_not_move_memberships_between_playlists
    fixture_xml = File.read(fixture_path('library.xml'))
    fixture_xml.sub!(%r{<key>Playlist ID</key>\s*<integer>1</integer>}, '')
    fixture_xml.sub!(%r{<key>Playlist ID</key>\s*<integer>4</integer>}, '')
    variant_path = write_xml('missing-playlist-ids.xml', fixture_xml)

    @importer.import(path: variant_path)

    manual_playlist = find_playlist_by_persistent_id('1111111111111111')
    empty_folder = find_playlist_by_persistent_id('4444444444444444')
    assert_equal 3, membership_count(manual_playlist.fetch('playlist_key'))
    assert_equal 0, membership_count(empty_folder.fetch('playlist_key'))
  end

  def test_import_report_counts_fields_and_warnings
    report = @importer.import(path: fixture_path('library.xml'))

    assert_equal 1, report.fetch(:warning_count)
    assert_equal 1, report.fetch(:warnings).first.fetch(:count)
    assert_equal 8, report.fetch(:field_counts).fetch('Rating').fetch(:present_count)
    assert_equal 0, report.fetch(:field_counts).fetch('Persistent ID').fetch(:missing_count)
    assert_equal IMPORT_TIME.iso8601(6), report.fetch(:imported_at)
    assert_operator report.fetch(:elapsed_s), :>=, 0
  end

  private

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def count_rows(table_name)
    @database.with_read do |connection|
      connection.get_first_value("SELECT COUNT(*) FROM \"#{table_name}\"").to_i
    end
  end

  def find_track(source_track_id:)
    @database.with_read do |connection|
      connection.get_first_row('SELECT * FROM tracks WHERE source_track_id = ?', source_track_id)
    end
  end

  def find_track_key(source_track_id:)
    find_track(source_track_id: source_track_id).fetch('track_key')
  end

  def find_playlist(source_playlist_id:)
    @database.with_read do |connection|
      connection.get_first_row('SELECT * FROM playlists WHERE source_playlist_id = ?', source_playlist_id)
    end
  end

  def find_playlist_key(source_playlist_id:)
    find_playlist(source_playlist_id: source_playlist_id).fetch('playlist_key')
  end

  def find_playlist_by_persistent_id(persistent_id)
    @database.with_read do |connection|
      connection.get_first_row('SELECT * FROM playlists WHERE persistent_id = ?', persistent_id)
    end
  end

  def membership_count(playlist_key)
    @database.with_read do |connection|
      connection.get_first_value('SELECT COUNT(*) FROM playlist_tracks WHERE playlist_key = ?', playlist_key).to_i
    end
  end

  def import_record
    @database.with_read do |connection|
      connection.get_first_row('SELECT * FROM library_import WHERE id = 1')
    end
  end

  def write_empty_library
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>Library Persistent ID</key><string>AAAAAAAAAAAAAAAA</string>
        <key>Tracks</key><dict/>
        <key>Playlists</key><array/>
      </dict></plist>
    XML
    write_xml('empty-library.xml', xml)
  end

  def write_xml(name, content)
    xml_path = File.join(@temporary_directory, name)
    File.write(xml_path, content)
    xml_path
  end
end
