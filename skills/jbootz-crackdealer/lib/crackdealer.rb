require 'fileutils'
require 'json'
require 'optparse'
require 'sqlite3'

module Crackdealer
  VERSION = '0.1.0'.freeze

  class Error < StandardError
    attr_reader :code, :exit_status

    def initialize(message, code: 'database_error', exit_status: 1)
      super(message)
      @code = code
      @exit_status = exit_status
    end
  end
end

require_relative 'crackdealer/database'
require_relative 'crackdealer/identity'
require_relative 'crackdealer/apple_library'
require_relative 'crackdealer/importer'
require_relative 'crackdealer/queries'
require_relative 'crackdealer/sql_reader'
require_relative 'crackdealer/history'
require_relative 'crackdealer/feedback'
require_relative 'crackdealer/cli'
