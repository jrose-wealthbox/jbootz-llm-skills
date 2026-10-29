require 'base64'

module Crackdealer
  class SqlReader
    DEFAULT_LIMIT = 100
    DEFAULT_TIMEOUT_MS = 5_000
    PRAGMA_ACTION = 19
    READ_ACTION = 20
    SELECT_ACTION = 21
    FUNCTION_ACTION = 31
    RECURSIVE_ACTION = 33
    ALLOWED_PRAGMAS = %w[table_info table_xinfo index_list index_info foreign_key_list].freeze
    BLOCKED_FUNCTIONS = %w[load_extension readfile writefile].freeze

    # sqlite3-ruby 2.10.1 forwards SQLITE_* authorizer action IDs unchanged from SQLite
    # (ext/sqlite3/database.c#rb_sqlite3_auth); this binding exports no action-ID constants.
    # Values are SQLITE_PRAGMA=19, SQLITE_READ=20, SQLITE_SELECT=21, SQLITE_FUNCTION=31,
    # and SQLITE_RECURSIVE=33 from the SQLite authorizer action enum. The bridge maps 0/1
    # to SQLITE_OK/SQLITE_DENY, so the callback returns these explicit integer values.
    AUTHORIZER_OK = 0
    AUTHORIZER_DENY = 1

    def initialize(database:)
      @database = database
    end

    def query(sql:, limit: DEFAULT_LIMIT, offset: 0, timeout_ms: DEFAULT_TIMEOUT_MS)
      validate_query!(sql, limit, offset, timeout_ms)
      @database.with_read do |connection|
        connection.results_as_hash = false
        connection.enable_load_extension(false)
        connection.statement_timeout = timeout_ms
        connection.authorizer = method(:authorize)
        execute_single_statement(connection, sql, limit, offset)
      end
    rescue Crackdealer::Error
      raise
    rescue SQLite3::InterruptException, SQLite3::BusyException => error
      raise timeout_error, cause: error
    rescue SQLite3::AuthorizationException, SQLite3::ReadOnlyException => error
      raise denied_error, cause: error
    rescue SQLite3::SQLException => error
      if error.message.match?(/not authorized|authorization denied/i)
        raise denied_error, cause: error
      end
      if error.message.match?(/interrupted/i)
        raise timeout_error, cause: error
      end
      raise invalid_query_error, cause: error
    rescue SQLite3::Exception => error
      raise Error.new('SQL query failed.', code: 'database_error'), cause: error
    end

    private

    def authorize(action_code, first_argument, second_argument, _third_argument, _fourth_argument)
      case action_code
      when READ_ACTION, SELECT_ACTION, RECURSIVE_ACTION
        AUTHORIZER_OK
      when FUNCTION_ACTION
        function_name = (second_argument || first_argument).to_s.downcase
        BLOCKED_FUNCTIONS.include?(function_name) ? AUTHORIZER_DENY : AUTHORIZER_OK
      when PRAGMA_ACTION
        ALLOWED_PRAGMAS.include?(first_argument.to_s.downcase) ? AUTHORIZER_OK : AUTHORIZER_DENY
      else
        AUTHORIZER_DENY
      end
    end

    def execute_single_statement(connection, sql, limit, offset)
      statement = nil
      result_set = nil
      begin
        statement = connection.prepare(sql)
        raise invalid_query_error if statement.nil? || statement.closed?

        unless statement.remainder.to_s.strip.empty?
          raise denied_error
        end

        columns = statement.columns
        paged_sql = pageable_sql(sql)
        if paged_sql
          statement.close
          statement = connection.prepare("SELECT * FROM (\n#{paged_sql}\n) LIMIT ? OFFSET ?")
          page_limit = limit.zero? ? -1 : limit + 1
          result_set = statement.execute(page_limit, offset)
          offset = 0
        else
          result_set = statement.execute
        end
        rows = []
        truncated = false
        row_index = 0
        result_set.each do |database_row|
          if row_index < offset
            row_index += 1
            next
          end
          if limit.positive? && rows.length >= limit
            truncated = true
            break
          end

          rows << database_row.map { |value| encode_value(value) }
          row_index += 1
        end
        { columns: columns, rows: rows, truncated: truncated }
      ensure
        result_set.close if result_set && !result_set.closed?
        statement.close if statement && !statement.closed?
      end
    end

    def pageable_sql(sql)
      return nil unless sql.match?(/\A(?:\s|--[^\n]*(?:\n|\z)|\/\*.*?\*\/)*(?:SELECT|WITH)\b/im)

      sql.sub(/;\s*\z/, '').strip
    end

    def encode_value(value)
      is_blob = value.is_a?(SQLite3::Blob) || (value.is_a?(String) && value.encoding == Encoding::BINARY)
      return value unless is_blob

      { 'base64' => Base64.strict_encode64(value.to_s.b) }
    end

    def validate_query!(sql, limit, offset, timeout_ms)
      unless sql.is_a?(String) && !sql.strip.empty?
        raise Error.new('SQL query must be a nonempty string.', code: 'invalid_input', exit_status: 2)
      end
      unless limit.is_a?(Integer) && limit >= 0 && offset.is_a?(Integer) && offset >= 0
        raise Error.new('SQL limit and offset must be nonnegative integers.', code: 'invalid_input', exit_status: 2)
      end
      unless timeout_ms.is_a?(Integer) && timeout_ms.positive?
        raise Error.new('SQL timeout_ms must be a positive integer.', code: 'invalid_input', exit_status: 2)
      end
    end

    def denied_error
      Error.new('SQL statement is not allowed by the read-only policy.', code: 'sql_denied', exit_status: 2)
    end

    def invalid_query_error
      Error.new('SQL query is invalid or unsupported.', code: 'invalid_input', exit_status: 2)
    end

    def timeout_error
      Error.new('SQL query exceeded timeout_ms.', code: 'query_timeout', exit_status: 1)
    end
  end
end
