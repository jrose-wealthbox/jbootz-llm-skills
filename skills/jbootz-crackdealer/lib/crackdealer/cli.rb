module Crackdealer
  module CLI
    HELP_TEXT = <<~HELP.freeze
      Usage: bundle exec ruby bin/crackdealer [--db PATH] COMMAND [OPTIONS]

      Commands:
        init       Create the database and schema
        status     Show library snapshot and history counts
        schema     Describe tables and columns
        import     Import an Apple Music XML snapshot
        tracks     Search tracks and evidence
        playlists  Search playlists
        playlist   Show ordered playlist membership
        sql        Run one read-only SQL statement
        session    Record a recommendation request
        recommendation Record selected recommendations
        history    Read or export recommendation history
        feedback   Record, retract, or inspect contextual feedback

      Global options:
        --db PATH  Database path (overrides CRACKDEALER_DB)
        --help     Show command help
        --version  Show version
    HELP

    COMMAND_HELP = {
      'init' => 'Usage: crackdealer [--db PATH] init',
      'status' => 'Usage: crackdealer [--db PATH] status',
      'schema' => 'Usage: crackdealer [--db PATH] schema',
      'import' => 'Usage: crackdealer [--db PATH] import XML_PATH [--allow-empty]',
      'tracks' => 'Usage: crackdealer [--db PATH] tracks [--search TEXT] [--artist TEXT] [--playlist KEY] [--signal SIGNAL] [--limit N] [--offset N]',
      'playlists' => 'Usage: crackdealer [--db PATH] playlists [--search TEXT] [--limit N] [--offset N]',
      'playlist' => 'Usage: crackdealer [--db PATH] playlist KEY [--limit N] [--offset N]',
      'sql' => 'Usage: crackdealer [--db PATH] sql (--query SQL OR --file PATH) [--limit N] [--offset N] [--timeout-ms N]',
      'session' => 'Usage: crackdealer [--db PATH] session add --file PATH',
      'recommendation' => 'Usage: crackdealer [--db PATH] recommendation add --file PATH',
      'history' => "Usage: crackdealer [--db PATH] history [--session-id ID] [--recording-key KEY] [--artist TEXT] [--context-key KEY] [--limit N] [--offset N]\n       crackdealer [--db PATH] history export",
      'feedback' => "Usage: crackdealer [--db PATH] feedback add --file PATH\n       crackdealer [--db PATH] feedback retract EVENT_ID\n       crackdealer [--db PATH] feedback list (--recommendation-id ID OR --artist TEXT --title TEXT) [--version-label TEXT] [--context-key KEY] [--limit N] [--offset N]"
    }.freeze

    def self.run(argv, out: $stdout, err: $stderr, input: $stdin)
      arguments = argv.dup
      global_options = { db_path: nil, help: false, version: false }
      global_parser = OptionParser.new do |parser|
        parser.on('--db PATH', 'Database path') { |path| global_options[:db_path] = path }
        parser.on('-h', '--help', 'Show help') { global_options[:help] = true }
        parser.on('--version', 'Show version') { global_options[:version] = true }
      end
      global_parser.order!(arguments)

      if global_options[:help]
        out.write(HELP_TEXT)
        return 0
      end
      if global_options[:version]
        out.puts(VERSION)
        return 0
      end

      command = arguments.shift
      return show_command_help(command, out) if command && extract_help!(arguments)
      if command.nil? && arguments.empty? && argv.empty?
        out.write(HELP_TEXT)
        return 0
      end
      return invalid_command('A command is required.', err) if command.nil?

      database = build_database(global_options[:db_path])
      case command
      when 'init'
        reject_extra_arguments!(command, arguments)
        database.initialize!
        emit_success({ schema_version: Database::SCHEMA_VERSION }, metadata(database), out)
      when 'status'
        reject_extra_arguments!(command, arguments)
        emit_success(status_data(database), metadata(database), out)
      when 'schema'
        reject_extra_arguments!(command, arguments)
        emit_success(schema_data(database), metadata(database), out)
      when 'import'
        import_report = import_data(database, arguments)
        emit_success(import_report, metadata(database), out)
      when 'tracks'
        response_data = track_list_data(database, arguments)
        emit_success(response_data, metadata(database), out)
      when 'playlists'
        response_data = playlist_list_data(database, arguments)
        emit_success(response_data, metadata(database), out)
      when 'playlist'
        response_data = playlist_membership_data(database, arguments)
        emit_success(response_data, metadata(database), out)
      when 'sql'
        response_data = sql_query_data(database, arguments, input)
        emit_success(response_data, metadata(database), out)
      when 'session'
        response_data = create_session_data(database, arguments, input)
        emit_success(response_data, metadata(database), out)
      when 'recommendation'
        response_data = add_recommendations_data(database, arguments, input)
        emit_success(response_data, metadata(database), out)
      when 'history'
        response_data = history_data(database, arguments)
        emit_success(response_data, metadata(database), out)
      when 'feedback'
        response_data = feedback_data(database, arguments, input)
        emit_success(response_data, metadata(database), out)
      else
        raise invalid_input_error("Unknown command: #{command}.")
      end
      0
    rescue Crackdealer::Error => error
      emit_error(error, err)
      error.exit_status
    rescue OptionParser::ParseError => error
      invalid_command(error.message, err)
    rescue SQLite3::Exception => error
      report_error(Error.new('Database operation failed.', code: 'database_error'), err)
    rescue SystemCallError, IOError => error
      report_error(Error.new('File operation failed.', code: 'io_error'), err)
    end

    def self.import_data(database, arguments)
      import_options = { allow_empty: false }
      import_parser = OptionParser.new do |parser|
        parser.on('--allow-empty', 'Allow an export with no tracks') { import_options[:allow_empty] = true }
      end
      import_parser.parse!(arguments)
      xml_path = arguments.shift
      raise invalid_input_error('An XML export path is required.') unless xml_path
      raise invalid_input_error('Unexpected arguments after the XML export path.') unless arguments.empty?

      Importer.new(database: database).import(path: xml_path, allow_empty: import_options[:allow_empty])
    end
    private_class_method :import_data

    def self.sql_query_data(database, arguments, input)
      options = { limit: SqlReader::DEFAULT_LIMIT, offset: 0, timeout_ms: SqlReader::DEFAULT_TIMEOUT_MS }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--query SQL', 'SQL statement to execute') { |value| options[:query] = value }
        option_parser.on('--file PATH', 'Read the SQL statement from a file, or - for stdin') { |value| options[:file] = value }
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
        option_parser.on('--timeout-ms N', Integer) { |value| options[:timeout_ms] = value }
      end
      parser.parse!(arguments)
      reject_extra_arguments!('sql', arguments)
      query_source_count = [options.key?(:query), options.key?(:file)].count(true)
      unless query_source_count == 1
        raise invalid_input_error('Provide exactly one of --query or --file.')
      end

      sql = if options.key?(:query)
        options.fetch(:query)
      elsif options.fetch(:file) == '-'
        input.read
      else
        File.read(options.fetch(:file))
      end
      result = SqlReader.new(database: database).query(
        sql: sql,
        limit: options.fetch(:limit),
        offset: options.fetch(:offset),
        timeout_ms: options.fetch(:timeout_ms)
      )
      {
        columns: result.fetch(:columns),
        rows: result.fetch(:rows),
        limit: options.fetch(:limit),
        offset: options.fetch(:offset),
        returned_count: result.fetch(:rows).length,
        truncated: result.fetch(:truncated)
      }
    end
    private_class_method :sql_query_data

    def self.create_session_data(database, arguments, input)
      action = arguments.shift
      raise invalid_input_error('Use `session add --file PATH`.') unless action == 'add'

      payload = read_json_file_option('session', arguments, input)
      unless payload.is_a?(Hash) && payload.key?('request') &&
          (payload.keys - %w[request context_key context]).empty?
        raise invalid_input_error('Session payload must contain request and optional context_key/context fields.')
      end
      History.new(database: database).create_session(**payload.transform_keys(&:to_sym))
    end
    private_class_method :create_session_data

    def self.add_recommendations_data(database, arguments, input)
      action = arguments.shift
      raise invalid_input_error('Use `recommendation add --file PATH`.') unless action == 'add'

      payload = read_json_file_option('recommendation', arguments, input)
      unless payload.is_a?(Hash) && (payload.keys - %w[session_id recommendations]).empty?
        raise invalid_input_error('Recommendation payload must contain session_id and recommendations.')
      end
      recommendations = History.new(database: database).add_recommendations(
        session_id: payload['session_id'],
        recommendations: payload['recommendations']
      )
      { recommendations: recommendations }
    end
    private_class_method :add_recommendations_data

    def self.read_json_file_option(command, arguments, input)
      options = {}
      parser = OptionParser.new do |option_parser|
        option_parser.on('--file PATH', 'Read a JSON payload from a file, or - for stdin') do |value|
          options[:file] = value
        end
      end
      parser.parse!(arguments)
      reject_extra_arguments!(command, arguments)
      raise invalid_input_error('A JSON payload path is required with --file.') unless options.key?(:file)

      json = options.fetch(:file) == '-' ? input.read : File.read(options.fetch(:file))
      JSON.parse(json)
    rescue JSON::ParserError => error
      raise invalid_input_error('JSON payload is malformed.'), cause: error
    end
    private_class_method :read_json_file_option

    def self.history_data(database, arguments)
      if arguments.first == 'export'
        arguments.shift
        reject_extra_arguments!('history export', arguments)
        return History.new(database: database).export
      end

      options = { limit: History::DEFAULT_LIMIT, offset: 0 }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--session-id ID') { |value| options[:session_id] = value }
        option_parser.on('--recording-key KEY') { |value| options[:recording_key] = value }
        option_parser.on('--artist TEXT') { |value| options[:artist] = value }
        option_parser.on('--context-key KEY') { |value| options[:context_key] = value }
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
      end
      parser.parse!(arguments)
      reject_extra_arguments!('history', arguments)
      result = History.new(database: database).list(**options)
      list_response(result, limit: options.fetch(:limit), offset: options.fetch(:offset))
    end
    private_class_method :history_data

    def self.feedback_data(database, arguments, input)
      action = arguments.shift
      feedback = Feedback.new(database: database)
      case action
      when 'add'
        payload = read_json_file_option('feedback', arguments, input)
        allowed_keys = %w[recommendation_id reaction scope note]
        unless payload.is_a?(Hash) && (payload.keys - allowed_keys).empty?
          raise invalid_input_error('Feedback payload must contain recommendation_id and reaction with optional scope/note.')
        end
        feedback.add(
          recommendation_id: payload['recommendation_id'],
          reaction: payload['reaction'],
          scope: payload.fetch('scope', 'context'),
          note: payload['note']
        )
      when 'retract'
        event_id = arguments.shift
        raise invalid_input_error('A feedback event ID is required.') unless event_id
        reject_extra_arguments!('feedback retract', arguments)
        feedback.retract(event_id: event_id)
      when 'list'
        feedback_list_data(feedback, arguments)
      else
        raise invalid_input_error('Use feedback add, retract, or list.')
      end
    end
    private_class_method :feedback_data

    def self.feedback_list_data(feedback, arguments)
      options = { limit: Feedback::DEFAULT_LIMIT, offset: 0 }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--recommendation-id ID') { |value| options[:recommendation_id] = value }
        option_parser.on('--artist TEXT') { |value| options[:artist] = value }
        option_parser.on('--title TEXT') { |value| options[:title] = value }
        option_parser.on('--version-label TEXT') { |value| options[:version_label] = value }
        option_parser.on('--context-key KEY') { |value| options[:context_key] = value }
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
      end
      parser.parse!(arguments)
      reject_extra_arguments!('feedback list', arguments)
      result = feedback.effective_for(**options)
      list_response(result, limit: options.fetch(:limit), offset: options.fetch(:offset))
    end
    private_class_method :feedback_list_data

    def self.track_list_data(database, arguments)
      options = {
        frequent_play_count: 10,
        low_play_count: 2,
        stale_days: 730,
        include_nonmusic: false,
        limit: 50,
        offset: 0
      }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--search TEXT', 'Literal substring search') { |value| options[:search] = value }
        option_parser.on('--artist TEXT', 'Artist substring filter') { |value| options[:artist] = value }
        option_parser.on('--playlist KEY', 'Playlist membership filter') { |value| options[:playlist_key] = value }
        option_parser.on('--signal SIGNAL', 'positive, negative, unexplored, or rediscover') { |value| options[:signal] = value }
        option_parser.on('--frequent-play-count N', Integer) { |value| options[:frequent_play_count] = value }
        option_parser.on('--low-play-count N', Integer) { |value| options[:low_play_count] = value }
        option_parser.on('--stale-days N', Integer) { |value| options[:stale_days] = value }
        option_parser.on('--include-nonmusic', 'Include Podcasts, Movies, TV shows, and Music Videos') do
          options[:include_nonmusic] = true
        end
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
      end
      parser.parse!(arguments)
      reject_extra_arguments!('tracks', arguments)
      queries = Queries.new(database: database)
      result = queries.tracks(**options)
      list_response(result, limit: options.fetch(:limit), offset: options.fetch(:offset))
    end
    private_class_method :track_list_data

    def self.playlist_list_data(database, arguments)
      options = { limit: 50, offset: 0 }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--search TEXT', 'Playlist name substring search') { |value| options[:search] = value }
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
      end
      parser.parse!(arguments)
      reject_extra_arguments!('playlists', arguments)
      result = Queries.new(database: database).playlists(**options)
      list_response(result, limit: options.fetch(:limit), offset: options.fetch(:offset))
    end
    private_class_method :playlist_list_data

    def self.playlist_membership_data(database, arguments)
      options = { limit: 50, offset: 0 }
      parser = OptionParser.new do |option_parser|
        option_parser.on('--limit N', Integer) { |value| options[:limit] = value }
        option_parser.on('--offset N', Integer) { |value| options[:offset] = value }
      end
      parser.parse!(arguments)
      playlist_key = arguments.shift
      raise invalid_input_error('A playlist key is required.') unless playlist_key
      reject_extra_arguments!('playlist', arguments)
      result = Queries.new(database: database).playlist(
        playlist_key: playlist_key,
        limit: options.fetch(:limit),
        offset: options.fetch(:offset)
      )
      list_response(result, limit: options.fetch(:limit), offset: options.fetch(:offset))
    end
    private_class_method :playlist_membership_data

    def self.list_response(result, limit:, offset:)
      rows = result.fetch(:rows)
      {
        rows: rows,
        limit: limit,
        offset: offset,
        returned_count: rows.length,
        truncated: result.fetch(:truncated)
      }
    end
    private_class_method :list_response

    def self.build_database(database_override)
      Database.new(path: Database.resolve_path(override: database_override))
    end
    private_class_method :build_database

    def self.extract_help!(arguments)
      help_index = arguments.index('--help') || arguments.index('-h')
      arguments.delete_at(help_index) if help_index
      !help_index.nil?
    end
    private_class_method :extract_help!

    def self.show_command_help(command, out)
      help_text = COMMAND_HELP[command]
      raise invalid_input_error("Unknown command: #{command}.") unless help_text

      out.puts(help_text)
      0
    end
    private_class_method :show_command_help

    def self.reject_extra_arguments!(command, arguments)
      return if arguments.empty?

      raise invalid_input_error("Unexpected arguments for #{command}: #{arguments.join(' ')}")
    end
    private_class_method :reject_extra_arguments!

    def self.status_data(database)
      database.with_read do |connection|
        snapshot_row = connection.get_first_row(
          'SELECT library_key, source_sha256, exported_at, imported_at, track_count, playlist_count FROM library_import WHERE id = 1'
        )
        snapshot = if snapshot_row
          {
            library_key: snapshot_row['library_key'],
            source_sha256: snapshot_row['source_sha256'],
            exported_at: snapshot_row['exported_at'],
            imported_at: snapshot_row['imported_at'],
            track_count: snapshot_row['track_count'],
            playlist_count: snapshot_row['playlist_count']
          }
        end
        {
          snapshot: snapshot,
          track_count: count_rows(connection, 'tracks'),
          playlist_count: count_rows(connection, 'playlists'),
          playlist_membership_count: count_rows(connection, 'playlist_tracks'),
          history_counts: {
            sessions: count_rows(connection, 'sessions'),
            recommendations: count_rows(connection, 'recommendations'),
            feedback_events: count_rows(connection, 'feedback_events')
          }
        }
      end
    end
    private_class_method :status_data

    def self.schema_data(database)
      database.with_read do |connection|
        table_rows = connection.execute(
          "SELECT name, sql FROM sqlite_schema WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
        tables = table_rows.map do |table_row|
          table_name = table_row.fetch('name')
          definition = table_row.fetch('sql')
          columns = connection.execute("PRAGMA table_info(#{quote_identifier(table_name)})").map do |column_row|
            {
              name: column_row.fetch('name'),
              type: column_row.fetch('type'),
              not_null: column_row.fetch('notnull').to_i == 1,
              default: column_row.fetch('dflt_value'),
              primary_key_position: column_row.fetch('pk').to_i
            }
          end
          { name: table_name, definition: definition, columns: columns }
        end
        { tables: tables }
      end
    end
    private_class_method :schema_data

    def self.metadata(database)
      database.with_read do |connection|
        {
          schema_version: connection.get_first_value('PRAGMA user_version').to_i,
          imported_at: connection.get_first_value('SELECT imported_at FROM library_import WHERE id = 1')
        }
      end
    end
    private_class_method :metadata

    def self.count_rows(connection, table_name)
      connection.get_first_value("SELECT COUNT(*) FROM #{quote_identifier(table_name)}").to_i
    end
    private_class_method :count_rows

    def self.quote_identifier(identifier)
      %Q("#{identifier.gsub('"', '""')}")
    end
    private_class_method :quote_identifier

    def self.emit_success(data, meta, out)
      out.puts(JSON.generate(data: data, meta: meta))
    end
    private_class_method :emit_success

    def self.invalid_input_error(message)
      Error.new(message, code: 'invalid_input', exit_status: 2)
    end
    private_class_method :invalid_input_error

    def self.invalid_command(message, err)
      report_error(invalid_input_error(message), err)
    end
    private_class_method :invalid_command

    def self.report_error(error, err)
      emit_error(error, err)
      error.exit_status
    end
    private_class_method :report_error

    def self.emit_error(error, err)
      err.puts(JSON.generate(error: { code: error.code, message: error.message }))
    end
    private_class_method :emit_error
  end
end
