module Crackdealer
  class Database
    SCHEMA_VERSION = 1
    BUSY_TIMEOUT_MS = 5_000

    attr_reader :path

    def self.default_path
      File.expand_path('../../data/crackdealer.sqlite3', __dir__)
    end

    def self.resolve_path(override: nil, env: ENV)
      selected_path = override
      selected_path = env['CRACKDEALER_DB'] if selected_path.nil?
      selected_path = default_path if selected_path.nil?

      unless selected_path.is_a?(String) && !selected_path.strip.empty?
        raise Error.new('Database path must be a nonblank filesystem path.', code: 'invalid_input', exit_status: 2)
      end

      File.expand_path(selected_path)
    end

    def initialize(path:)
      @path = File.expand_path(path)
    end

    def initialize!
      FileUtils.mkdir_p(File.dirname(path))
      connection = SQLite3::Database.new(path)
      configure_connection(connection, writer: true)
      connection.execute('PRAGMA journal_mode = DELETE')
      current_version = read_user_version(connection)

      if current_version > SCHEMA_VERSION
        raise unsupported_schema_error(current_version)
      end
      return nil if current_version == SCHEMA_VERSION

      if user_table_count(connection).positive?
        raise Error.new('Database has an unversioned schema and cannot be initialized safely.', code: 'database_error')
      end

      connection.transaction do
        connection.execute_batch(migration_sql)
        connection.execute("PRAGMA user_version = #{SCHEMA_VERSION}")
      end
      nil
    rescue Crackdealer::Error
      raise
    rescue SQLite3::Exception, SystemCallError => error
      raise Error.new('Database initialization failed.', code: 'database_error'), cause: error
    ensure
      connection&.close
    end

    def with_read
      connection = open_existing_connection(readonly: true)
      configure_connection(connection, writer: false)
      ensure_supported_schema!(connection)
      yield connection
    ensure
      connection&.close
    end

    def with_write
      connection = open_existing_connection(readonly: false)
      configure_connection(connection, writer: true)
      ensure_supported_schema!(connection)
      yield connection
    ensure
      connection&.close
    end

    def schema_version
      with_read { |connection| read_user_version(connection) }
    end

    private

    def open_existing_connection(readonly:)
      unless File.file?(path)
        raise Error.new('Database does not exist; run init first.', code: 'database_error')
      end

      if readonly
        SQLite3::Database.new(path, readonly: true)
      else
        SQLite3::Database.new(path)
      end
    rescue SQLite3::Exception, SystemCallError => error
      raise Error.new('Database could not be opened.', code: 'database_error'), cause: error
    end

    def configure_connection(connection, writer:)
      connection.busy_timeout = BUSY_TIMEOUT_MS
      connection.results_as_hash = true
      connection.execute('PRAGMA foreign_keys = ON') if writer
    end

    def ensure_supported_schema!(connection)
      current_version = read_user_version(connection)
      if current_version > SCHEMA_VERSION
        raise unsupported_schema_error(current_version)
      end
      return if current_version == SCHEMA_VERSION

      raise Error.new('Database is not initialized with a supported schema.', code: 'database_error')
    end

    def unsupported_schema_error(current_version)
      Error.new(
        "Database schema version #{current_version} is newer than supported version #{SCHEMA_VERSION}.",
        code: 'database_error'
      )
    end

    def read_user_version(connection)
      connection.get_first_value('PRAGMA user_version').to_i
    end

    def user_table_count(connection)
      connection.get_first_value(
        "SELECT COUNT(*) FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      ).to_i
    end

    def migration_sql
      migration_path = File.expand_path('../../db/migrations/001_initial.sql', __dir__)
      File.read(migration_path)
    end
  end
end
