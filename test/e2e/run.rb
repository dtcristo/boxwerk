#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end test runner for Boxwerk.
# Runs outside of minitest to test the full CLI → Box stack.
# Each test creates a temporary project, runs boxwerk commands via subprocess,
# and validates output and exit codes.
#
# Usage: RUBY_BOX=1 ruby test/e2e/run.rb

require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'open3'
require 'net/http'
require 'timeout'
require 'socket'

class E2ERunner
  attr_reader :pass_count, :fail_count

  def initialize
    @pass_count = 0
    @fail_count = 0
    @boxwerk_bin = File.expand_path('../../exe/boxwerk', __dir__)
  end

  def run_all
    puts 'Boxwerk E2E Tests'
    puts '=' * 60

    test_basic_run
    test_dependency_access
    test_transitive_blocked
    test_privacy_enforcement
    test_exec_ruby_script
    test_exec_missing_command
    test_version_command
    test_info_command
    test_help_command
    test_install_command
    test_missing_script_error
    test_nonexistent_script_error
    test_implicit_root
    test_nested_constants
    test_unknown_command_error
    test_package_flag_run
    test_package_flag_exec
    test_package_flag_unknown
    test_global_flag
    test_help_shows_global_flag
    test_console_root_package
    test_console_child_package
    test_console_global
    test_bundle_exec_reexec

    test_rails_db_migrate
    test_rails_runner
    test_rails_server_boots
    test_rails_server_responds
    test_rails_example_tests

    puts ''
    puts '=' * 60
    puts "#{@pass_count + @fail_count} tests: #{@pass_count} passed, #{@fail_count} failed"
    exit(@fail_count > 0 ? 1 : 0)
  end

  private

  def test_basic_run
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello from Boxwerk!'
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts Greeter.hello
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'basic_run: exit status'
      assert_match /Hello from Boxwerk!/, out, 'basic_run: output'
    end
  end

  def test_dependency_access
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/math'])
      create_package(dir, 'math')
      write_file(dir, 'packs/math/lib/calc.rb', <<~RUBY)
        class Calc
          def self.add(a, b) = a + b
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        result = Calc.add(3, 4)
        puts "Result: \#{result}"
        exit(result == 7 ? 0 : 1)
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'dependency_access: exit status'
      assert_match /Result: 7/, out, 'dependency_access: output'
    end
  end

  def test_transitive_blocked
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/a'])
      create_package(dir, 'a', dependencies: ['packs/b'])
      create_package(dir, 'b')
      write_file(dir, 'packs/a/lib/class_a.rb', "class ClassA; end\n")
      write_file(dir, 'packs/b/lib/class_b.rb', "class ClassB; end\n")
      write_file(dir, 'app.rb', <<~RUBY)
        begin
          ClassB
          puts "FAIL: transitive dependency was accessible"
          exit 1
        rescue NameError
          puts "PASS: transitive dependency blocked"
          exit 0
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'transitive_blocked: exit status'
      assert_match /PASS/, out, 'transitive_blocked: output'
    end
  end

  def test_privacy_enforcement
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/secure'])
      create_package(dir, 'secure', enforce_privacy: true)

      pub_dir = File.join(dir, 'packs', 'secure', 'public')
      FileUtils.mkdir_p(pub_dir)
      write_file(dir, 'packs/secure/public/api.rb', <<~RUBY)
        class Api
          def self.call = 'public api'
        end
      RUBY
      write_file(dir, 'packs/secure/lib/internal.rb', <<~RUBY)
        class Internal
          def self.secret = 'should not see this'
        end
      RUBY

      write_file(dir, 'app.rb', <<~RUBY)
        # Public constant should work
        puts Api.call

        # Private constant should raise
        begin
          Internal
          puts "FAIL: private constant accessible"
          exit 1
        rescue NameError => e
          if e.message.include?('private constant')
            puts "PASS: privacy enforced"
            exit 0
          else
            puts "FAIL: wrong error: \#{e.message}"
            exit 1
          end
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'privacy_enforcement: exit status'
      assert_match /public api/, out, 'privacy_enforcement: public access'
      assert_match /PASS/, out, 'privacy_enforcement: privacy block'
    end
  end

  def test_exec_ruby_script
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello via exec!'
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts Greeter.hello
      RUBY

      out, status = run_boxwerk(dir, 'exec', 'app.rb')
      assert_equal 0, status.exitstatus, 'exec_ruby_script: exit status'
      assert_match /Hello via exec!/, out, 'exec_ruby_script: output'
    end
  end

  def test_exec_missing_command
    out, status = run_boxwerk(Dir.pwd, 'exec')
    assert_equal 1, status.exitstatus, 'exec_missing_command: exit status'
    assert_match /No command specified/,
                 out,
                 'exec_missing_command: error message'
  end

  def test_version_command
    out, status = run_boxwerk(Dir.pwd, 'version')
    assert_equal 0, status.exitstatus, 'version: exit status'
    assert_match /boxwerk \d+\.\d+\.\d+/, out, 'version: output format'
  end

  def test_info_command
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/core'])
      create_package(dir, 'core')

      out, status = run_boxwerk(dir, 'info')
      assert_equal 0, status.exitstatus, 'info: exit status'
      assert_match /Dependency Graph/, out, 'info: shows dependency graph'
      assert_match %r{└── packs/core}, out, 'info: shows tree'
      assert_match /Packages/, out, 'info: shows packages section'
    end
  end

  def test_help_command
    out, status = run_boxwerk(Dir.pwd, 'help')
    assert_equal 0, status.exitstatus, 'help: exit status'
    assert_match /Usage:/, out, 'help: shows usage'
    assert_match /Commands:/, out, 'help: shows commands'
    assert_match /install/, out, 'help: shows install command'
    assert_match /exec/, out, 'help: shows exec command'
    assert_match /--package/, out, 'help: shows package flag'
  end

  def test_install_command
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/a'])
      create_package(dir, 'a')
      out, status = run_boxwerk(dir, 'install')
      assert_equal 0, status.exitstatus, 'install_no_gemfiles: exit status'
      assert_match /No packages with a Gemfile or gems\.rb found/,
                   out,
                   'install_no_gemfiles: output'
    end
  end

  def test_missing_script_error
    out, status = run_boxwerk(Dir.pwd, 'run')
    assert_equal 1, status.exitstatus, 'missing_script: exit status'
    assert_match /No script specified/, out, 'missing_script: error message'
  end

  def test_nonexistent_script_error
    out, status = run_boxwerk(Dir.pwd, 'run', 'nonexistent.rb')
    assert_equal 1, status.exitstatus, 'nonexistent_script: exit status'
    assert_match /Script not found/, out, 'nonexistent_script: error message'
  end

  def test_implicit_root
    Dir.mktmpdir do |dir|
      write_file(dir, 'app.rb', "puts 'hello from implicit root'\n")
      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'implicit_root: exit status'
      assert_match /hello from implicit root/, out, 'implicit_root: script runs'
    end
  end

  def test_nested_constants
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/api'])
      create_package(dir, 'api')
      FileUtils.mkdir_p(File.join(dir, 'packs', 'api', 'lib', 'v2'))
      write_file(dir, 'packs/api/lib/v2/endpoint.rb', <<~RUBY)
        module V2
          class Endpoint
            def self.path = '/api/v2'
          end
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts V2::Endpoint.path
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, 'nested_constants: exit status'
      assert_match %r{/api/v2}, out, 'nested_constants: output'
    end
  end

  def test_unknown_command_error
    out, status = run_boxwerk(Dir.pwd, 'foobar')
    assert_equal 1, status.exitstatus, 'unknown_command: exit status'
    assert_match /Unknown command/, out, 'unknown_command: error message'
  end

  def test_package_flag_run
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello from greeter pack!'
        end
      RUBY
      write_file(dir, 'script.rb', <<~RUBY)
        puts Greeter.hello
      RUBY

      # Run in root package (has access to greeter via dependency)
      out, status = run_boxwerk(dir, 'run', '-p', '.', 'script.rb')
      assert_equal 0, status.exitstatus, 'package_flag_run: exit status'
      assert_match /Hello from greeter pack!/, out, 'package_flag_run: output'
    end
  end

  def test_package_flag_exec
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello via exec!'
        end
      RUBY
      write_file(dir, 'script.rb', <<~RUBY)
        puts Greeter.hello
      RUBY

      out, status = run_boxwerk(dir, 'exec', '-p', '.', 'script.rb')
      assert_equal 0, status.exitstatus, 'package_flag_exec: exit status'
      assert_match /Hello via exec!/, out, 'package_flag_exec: output'
    end
  end

  def test_package_flag_unknown
    with_project do |dir|
      create_root_package(dir)
      write_file(dir, 'app.rb', "puts 'hello'\n")
      out, status = run_boxwerk(dir, 'run', '-p', 'packs/nonexistent', 'app.rb')
      assert_equal 1, status.exitstatus, 'package_flag_unknown: exit status'
      assert_match /Unknown package/, out, 'package_flag_unknown: error message'
    end
  end

  def test_global_flag
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello!'
        end
      RUBY
      write_file(dir, 'script.rb', <<~RUBY)
        begin
          _ = Greeter
          puts "FAIL: Greeter should not be accessible in global context"
          exit 1
        rescue NameError
          puts "PASS: global context has no package constants"
          exit 0
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', '--global', 'script.rb')
      assert_equal 0, status.exitstatus, 'global_flag: exit status'
      assert_match /PASS/,
                   out,
                   'global_flag: no package constants in global context'

      # Also test -g alias
      out2, status2 = run_boxwerk(dir, 'run', '-g', 'script.rb')
      assert_equal 0, status2.exitstatus, 'global_flag: -g alias exit status'
      assert_match /PASS/, out2, 'global_flag: -g alias works'
    end
  end

  def test_help_shows_global_flag
    out, status = run_boxwerk(Dir.pwd, 'help')
    assert_match /--global/, out, 'help: shows --global option'
  end

  def test_console_root_package
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Console Hello!'
        end
      RUBY

      out, status =
        run_boxwerk_with_stdin(dir, "puts Greeter.hello\nexit\n", 'console')
      assert_equal 0, status.exitstatus, 'console_root_package: exit status'
      assert_match /Console Hello!/,
                   out,
                   'console_root_package: resolves dependency constant'
      assert_match /console \(\.\)/,
                   out,
                   'console_root_package: shows (.) label'
    end
  end

  def test_console_child_package
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'From greeter!'
        end
      RUBY

      out, status =
        run_boxwerk_with_stdin(
          dir,
          "puts Greeter.hello\nexit\n",
          'console',
          '-p',
          'packs/greeter',
        )
      assert_equal 0, status.exitstatus, 'console_child_package: exit status'
      assert_match /From greeter!/,
                   out,
                   'console_child_package: resolves own constant'
    end
  end

  def test_console_global
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello!'
        end
      RUBY

      # Global context should not have access to package constants
      script = <<~STDIN
        begin
          _ = Greeter
          puts "FAIL"
        rescue NameError
          puts "PASS: no package constants"
        end
        exit
      STDIN
      out, status = run_boxwerk_with_stdin(dir, script, 'console', '--global')
      assert_equal 0, status.exitstatus, 'console_global: exit status'
      assert_match /PASS/,
                   out,
                   'console_global: no package constants in global context'
    end
  end

  def test_bundle_exec_reexec
    with_project do |dir|
      create_root_package(dir, dependencies: ['packs/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packs/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello via bundle exec!'
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts Greeter.hello
      RUBY

      # Simulate Bundler being loaded (as with bundle exec or binstub)
      # by pre-requiring bundler via RUBYOPT. The re-exec should strip this.
      gemfile = File.expand_path('../../gems.rb', __dir__)
      env = {
        'RUBY_BOX' => '1',
        'RUBYOPT' => '-rbundler/setup',
        'BUNDLE_GEMFILE' => gemfile,
      }
      cmd = ['ruby', @boxwerk_bin, 'run', 'app.rb']
      stdout, stderr, status = Open3.capture3(env, *cmd, chdir: dir)
      out = stdout + stderr
      assert_equal 0, status.exitstatus, 'bundle_exec_reexec: exit status'
      assert_match /Hello via bundle exec!/, out, 'bundle_exec_reexec: output'
    end
  end

  # --- Rails example tests ---

  def test_rails_db_migrate
    db_path = File.join(rails_dir, 'db', 'test.sqlite3')
    FileUtils.rm_f(db_path)

    out, status = run_rails_boxwerk('exec', '-g', 'rails', 'db:migrate')
    assert_equal 0, status.exitstatus, 'rails_db_migrate: exit status'
    assert_equal true, File.exist?(db_path), 'rails_db_migrate: db file created'
  end

  def test_rails_runner
    out, status =
      run_rails_boxwerk(
        'exec',
        '-g',
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

  def test_rails_example_tests
    out, status = run_rails_boxwerk('exec', '--all', 'rake', 'test')
    assert_equal 0, status.exitstatus, 'rails_example_tests: exit status'
    assert_match(/\d+ runs/, out, 'rails_example_tests: test results')
  end

  # --- Helpers ---

  def with_project
    Dir.mktmpdir { |dir| yield dir }
  end

  def run_boxwerk(dir, *args)
    gemfile = File.expand_path('../../gems.rb', __dir__)
    env = { 'RUBY_BOX' => '1' }
    cmd = ['ruby', @boxwerk_bin, *args]
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: dir)
    [stdout + stderr, status]
  end

  def run_boxwerk_with_stdin(dir, input, *args)
    env = { 'RUBY_BOX' => '1' }
    cmd = ['ruby', @boxwerk_bin, *args]
    stdout, stderr, status =
      Open3.capture3(env, *cmd, stdin_data: input, chdir: dir)
    [stdout + stderr, status]
  end

  def create_root_package(dir, dependencies: [])
    content = { 'enforce_dependencies' => true }
    content['dependencies'] = dependencies if dependencies.any?
    File.write(File.join(dir, 'package.yml'), YAML.dump(content))
  end

  def create_package(dir, name, dependencies: nil, enforce_privacy: false)
    pkg_dir = File.join(dir, 'packs', name)
    FileUtils.mkdir_p(File.join(pkg_dir, 'lib'))
    content = { 'enforce_dependencies' => true }
    content['dependencies'] = dependencies if dependencies
    content['enforce_privacy'] = true if enforce_privacy
    File.write(File.join(pkg_dir, 'package.yml'), YAML.dump(content))
  end

  def write_file(dir, path, content)
    full_path = File.join(dir, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
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

  # --- Rails helpers ---

  def rails_dir
    @rails_dir ||= File.expand_path('../../examples/rails', __dir__)
  end

  def rails_boxwerk_bin
    @rails_boxwerk_bin ||= File.join(rails_dir, 'bin', 'boxwerk')
  end

  def run_rails_boxwerk(*args)
    env = { 'RUBY_BOX' => '1', 'RAILS_ENV' => 'test' }
    cmd = ['ruby', rails_boxwerk_bin, *args]
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: rails_dir)
    [stdout + stderr, status]
  end

  def rails_migrate_test_db
    run_rails_boxwerk('exec', '-g', 'rails', 'db:migrate')
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
      rails_boxwerk_bin,
      'exec',
      '-g',
      'rails',
      'server',
      '-p',
      port.to_s,
    ]
    Process.spawn(env, *cmd, chdir: rails_dir, out: File::NULL, err: File::NULL)
  end

  def stop_process(pid)
    Process.kill('TERM', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    # Process already exited
  end
end

E2ERunner.new.run_all
