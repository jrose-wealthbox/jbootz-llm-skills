require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'sqlite3'
require 'stringio'
require 'tmpdir'

library_path = File.expand_path('../lib/crackdealer.rb', __dir__)
require library_path if File.file?(library_path)

class CrackdealerTest < Minitest::Test
  def setup
    @temporary_directory = Dir.mktmpdir('crackdealer-test-')
    @database_path = File.join(@temporary_directory, 'test.sqlite3')
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory && File.exist?(@temporary_directory)
  end

  def build_database(path: @database_path)
    assert_equal 'constant', defined?(Crackdealer::Database), 'database implementation is not loaded yet'
    Crackdealer::Database.new(path: path)
  end

  def run_cli(arguments, input: '')
    assert_equal 'constant', defined?(Crackdealer::CLI), 'CLI implementation is not loaded yet'
    output = StringIO.new
    error_output = StringIO.new
    exit_status = Crackdealer::CLI.run(
      arguments,
      out: output,
      err: error_output,
      input: StringIO.new(input)
    )
    [exit_status, output.string, error_output.string]
  end
end
