#!/usr/bin/env ruby
# frozen_string_literal: true

# Rails example e2e tests.
# Usage: RUBY_BOX=1 ruby examples/rails/test/e2e_test.rb

require 'open3'
require 'fileutils'
require 'net/http'
require 'timeout'
require 'socket'

class RailsE2ERunner
  attr_reader :pass_count, :fail_count

  def initialize
    @pass_count = 0
    @fail_count = 0
    @rails_dir = File.expand_path('..', __dir__)
    @boxwerk_bin = File.join(@rails_dir, 'bin', 'boxwerk')
  end

  def run_all
    puts 'Rails E2E Tests'
    puts '=' * 60

    test_rails_db_migrate
    test_rails_runner
    test_rails_server_boots
    test_rails_server_responds

    puts ''
    puts '=' * 60
    puts "#{@pass_count + @fail_count} tests: #{@pass_count} passed, #{@fail_count} failed"
    exit(@fail_count > 0 ? 1 : 0)
  end

  private

  def test_rails_db_migrate
    db_path = File.join(@rails_dir, 'db', 'test.sqlite3')
    FileUtils.rm_f(db_path)

    out, status = run_rails_boxwerk('exec', 'rails', 'db:migrate')
    assert_equal 0, status.exitstatus, 'rails_db_migrate: exit status'
    assert_equal true, File.exist?(db_path), 'rails_db_migrate: db file created'
  end

  def test_rails_runner
    out, status =
      run_rails_boxwerk(
        'exec',
        'rails',
        'runner',
        'puts ENV["RAILS_ENV"]',
      )
    assert_equal 0, status.exitstatus, 'rails_runner: exit status'
    assert_match(/test/, out, 'rails_runner: RAILS_ENV output')
  end

  def test_rails_server_boots
    rails_migrate_test_db
    port = available_port
    pid = start_rails_server(port)

    begin
      alive = false
      Timeout.timeout(10) do
        loop do
          Process.kill(0, pid)
          alive = true
          break
        rescue Errno::ESRCH
          sleep 0.5
        end
      end
      assert_equal true, alive, 'rails_server_boots: process is alive'
    ensure
      stop_process(pid)
    end
  end

  def test_rails_server_responds
    rails_migrate_test_db
    port = available_port
    pid = start_rails_server(port)

    begin
      response = nil
      Timeout.timeout(15) do
        loop do
          response =
            Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/users"))
          break
        rescue Errno::ECONNREFUSED
          sleep 1
        end
      end

      assert_equal false, response.nil?, 'rails_server_responds: got response'
      assert_match(
        /\d{3}/,
        response.code,
        'rails_server_responds: valid HTTP status',
      )
    ensure
      stop_process(pid)
    end
  end

  # --- Helpers ---

  def run_rails_boxwerk(*args)
    env = { 'RUBY_BOX' => '1', 'RAILS_ENV' => 'test' }
    cmd = ['ruby', @boxwerk_bin, *args]
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: @rails_dir)
    [stdout + stderr, status]
  end

  def rails_migrate_test_db
    run_rails_boxwerk('exec', 'rails', 'db:migrate')
  end

  def available_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  def start_rails_server(port)
    env = { 'RUBY_BOX' => '1', 'RAILS_ENV' => 'test' }
    cmd = [
      'ruby',
      @boxwerk_bin,
      'exec',
      'rails',
      'server',
      '-p',
      port.to_s,
    ]
    Process.spawn(
      env,
      *cmd,
      chdir: @rails_dir,
      pgroup: true,
      out: File::NULL,
      err: File::NULL,
    )
  end

  def stop_process(pid)
    Process.kill('TERM', -pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    # Process already exited
  end

  def assert_equal(expected, actual, label)
    if expected == actual
      @pass_count += 1
      puts "  ✓ #{label}"
    else
      @fail_count += 1
      puts "  ✗ #{label}: expected #{expected.inspect}, got #{actual.inspect}"
    end
  end

  def assert_match(pattern, string, label)
    if string.match?(pattern)
      @pass_count += 1
      puts "  ✓ #{label}"
    else
      @fail_count += 1
      puts "  ✗ #{label}: #{pattern.inspect} not found in output"
      puts "    Output: #{string[0..200]}"
    end
  end
end

RailsE2ERunner.new.run_all
