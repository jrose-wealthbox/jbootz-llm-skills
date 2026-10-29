require 'fileutils'
require 'json'
require 'optparse'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'crackdealer'

module CrackdealerBenchmark
  DEFAULT_TRACK_COUNT = 40_000
  TRACK_METADATA_BYTES = 1_800
  PLAYLIST_COUNT = 4
  MEMBERSHIPS_PER_PLAYLIST = 1_000

  module_function

  def run(arguments)
    options = { track_count: DEFAULT_TRACK_COUNT }
    parser = OptionParser.new do |option_parser|
      option_parser.banner = 'Usage: ruby script/benchmark_import.rb [--track-count N]'
      option_parser.on('--track-count N', Integer, 'Number of synthetic tracks') do |track_count|
        options[:track_count] = track_count
      end
      option_parser.on('--help', 'Show help') do
        puts option_parser
        return 0
      end
    end
    parser.parse!(arguments)
    unless options[:track_count].is_a?(Integer) && options[:track_count].positive?
      raise ArgumentError, '--track-count must be a positive integer.'
    end
    raise ArgumentError, 'Unexpected benchmark arguments.' unless arguments.empty?

    Dir.mktmpdir('crackdealer-benchmark-') do |temporary_directory|
      source_path = File.join(temporary_directory, 'synthetic-library.xml')
      database_path = File.join(temporary_directory, 'synthetic-library.sqlite3')
      write_synthetic_library(source_path, options.fetch(:track_count))
      source_size_bytes = File.size(source_path)
      database = Crackdealer::Database.new(path: database_path)
      importer = Crackdealer::Importer.new(database: database)
      first_import = importer.import(path: source_path)
      assert_equal(options.fetch(:track_count), first_import.fetch(:track_count), 'first import track count')
      assert_equal(PLAYLIST_COUNT, first_import.fetch(:playlist_count), 'first import playlist count')

      history = Crackdealer::History.new(database: database)
      session = history.create_session(request: 'Benchmark history survives library refresh')
      first_track_key = database.with_read do |connection|
        connection.get_first_value('SELECT track_key FROM tracks WHERE source_track_id = 1')
      end
      history.add_recommendations(
        session_id: session.fetch(:id),
        recommendations: [{
          artist: 'Benchmark Artist 1',
          title: 'Benchmark Track 000001',
          reason: 'Synthetic benchmark history',
          library_track_key: first_track_key
        }]
      )
      history_counts_before_repeat = history_counts(database)

      repeat_import = importer.import(path: source_path)
      assert_equal(options.fetch(:track_count), repeat_import.fetch(:track_count), 'repeat import track count')
      history_counts_after_repeat = history_counts(database)
      assert_equal(history_counts_before_repeat, history_counts_after_repeat, 'history counts after repeat import')
      membership_count = count_rows(database, 'playlist_tracks')
      expected_membership_count = [MEMBERSHIPS_PER_PLAYLIST, options.fetch(:track_count)].min * PLAYLIST_COUNT
      assert_equal(expected_membership_count, membership_count, 'playlist membership count')

      query_started_at_s = monotonic_time_s
      filtered_rows = Crackdealer::Queries.new(database: database).tracks(
        artist: 'Benchmark Artist 42',
        signal: 'positive',
        limit: 100
      ).fetch(:rows)
      filtered_query_elapsed_s = monotonic_time_s - query_started_at_s

      aggregate_started_at_s = monotonic_time_s
      aggregate_result = Crackdealer::SqlReader.new(database: database).query(
        sql: <<~SQL,
          SELECT COUNT(*) AS track_count, COUNT(DISTINCT artist_normalized) AS artist_count,
            SUM(CASE WHEN rating_100 >= 80 THEN 1 ELSE 0 END) AS highly_rated_count,
            (SELECT COUNT(*) FROM playlist_tracks) AS playlist_membership_count
          FROM tracks
        SQL
        limit: 1
      )
      aggregate_query_elapsed_s = monotonic_time_s - aggregate_started_at_s
      aggregate_row = aggregate_result.fetch(:rows).first
      assert_equal(options.fetch(:track_count), aggregate_row[0], 'aggregate track count')
      assert_equal(membership_count, aggregate_row[3], 'aggregate membership count')

      report = {
        track_count: options.fetch(:track_count),
        playlist_count: first_import.fetch(:playlist_count),
        playlist_membership_count: membership_count,
        source_size_bytes: source_size_bytes,
        database_size_bytes: File.size(database_path),
        elapsed_s: first_import.fetch(:elapsed_s),
        repeat_import_elapsed_s: repeat_import.fetch(:elapsed_s),
        filtered_query_elapsed_s: filtered_query_elapsed_s,
        filtered_result_count: filtered_rows.length,
        aggregate_query_elapsed_s: aggregate_query_elapsed_s,
        aggregate_result: {
          track_count: aggregate_row[0],
          artist_count: aggregate_row[1],
          highly_rated_count: aggregate_row[2],
          playlist_membership_count: aggregate_row[3]
        },
        history_counts_before_repeat_import: history_counts_before_repeat,
        history_counts_after_repeat_import: history_counts_after_repeat
      }
      puts JSON.pretty_generate(report)
    end
    0
  rescue ArgumentError => error
    warn error.message
    2
  end

  def write_synthetic_library(path, track_count)
    metadata_text = 'x' * TRACK_METADATA_BYTES
    File.open(path, 'wb') do |file|
      file.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
      file.write("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n")
      file.write("<plist version=\"1.0\"><dict>\n")
      file.write("<key>Major Version</key><integer>1</integer>\n")
      file.write("<key>Minor Version</key><integer>1</integer>\n")
      file.write("<key>Application Version</key><string>1.4.3</string>\n")
      file.write("<key>Library Persistent ID</key><string>BENCHMARKLIBRARY</string>\n")
      file.write("<key>Tracks</key><dict>\n")
      (1..track_count).each do |source_track_id|
        rating = case source_track_id % 4
        when 0 then '<key>Rating</key><integer>100</integer>'
        when 1 then '<key>Rating</key><integer>20</integer>'
        else ''
        end
        file.write("<key>#{source_track_id}</key><dict>")
        file.write("<key>Track ID</key><integer>#{source_track_id}</integer>")
        file.write("<key>Persistent ID</key><string>#{format('%016X', source_track_id)}</string>")
        file.write("<key>Name</key><string>Benchmark Track #{format('%06d', source_track_id)}</string>")
        file.write("<key>Artist</key><string>Benchmark Artist #{source_track_id % 100}</string>")
        file.write("<key>Album</key><string>Benchmark Album #{source_track_id % 20}</string>")
        file.write("<key>Genre</key><string>Experimental Folk</string>")
        file.write(rating)
        file.write("<key>Play Count</key><integer>#{source_track_id % 12}</integer>")
        file.write("<key>Comments</key><string>#{metadata_text}</string>")
        file.write("</dict>\n")
      end
      file.write("</dict>\n<key>Playlists</key><array>\n")
      membership_count = [MEMBERSHIPS_PER_PLAYLIST, track_count].min
      (1..PLAYLIST_COUNT).each do |playlist_index|
        playlist_id = 10_000 + playlist_index
        file.write("<dict><key>Playlist ID</key><integer>#{playlist_id}</integer>")
        file.write("<key>Persistent ID</key><string>#{format('PLAYLIST%08d', playlist_index)}</string>")
        file.write("<key>Name</key><string>Benchmark Playlist #{playlist_index}</string>")
        file.write("<key>Playlist Items</key><array>")
        membership_count.times do |membership_index|
          source_track_id = ((membership_index + (playlist_index - 1) * membership_count) % track_count) + 1
          file.write("<dict><key>Track ID</key><integer>#{source_track_id}</integer></dict>")
        end
        file.write("</array></dict>\n")
      end
      file.write("</array></dict></plist>\n")
    end
  end

  def history_counts(database)
    %w[sessions recommendations feedback_events].to_h do |table_name|
      [table_name, count_rows(database, table_name)]
    end
  end

  def count_rows(database, table_name)
    database.with_read { |connection| connection.get_first_value("SELECT COUNT(*) FROM #{table_name}").to_i }
  end

  def assert_equal(expected, actual, description)
    return if expected == actual

    raise RuntimeError, "#{description} expected #{expected.inspect}, got #{actual.inspect}"
  end

  def monotonic_time_s
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

exit CrackdealerBenchmark.run(ARGV)
