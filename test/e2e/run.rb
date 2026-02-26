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

class E2ERunner
  attr_reader :pass_count, :fail_count

  def initialize
    @pass_count = 0
    @fail_count = 0
    @boxwerk_bin = File.expand_path('../../exe/boxwerk', __dir__)
  end

  def run_all
    puts "Boxwerk E2E Tests"
    puts "=" * 60

    test_basic_run
    test_dependency_access
    test_transitive_blocked
    test_privacy_enforcement
    test_version_command
    test_info_command
    test_help_command
    test_missing_script_error
    test_nonexistent_script_error
    test_missing_package_yml_error
    test_layer_violation_at_boot
    test_visibility_enforcement
    test_nested_constants
    test_unknown_command_error

    puts ""
    puts "=" * 60
    puts "#{@pass_count + @fail_count} tests: #{@pass_count} passed, #{@fail_count} failed"
    exit(@fail_count > 0 ? 1 : 0)
  end

  private

  def test_basic_run
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/greeter'])
      create_package(dir, 'greeter')
      write_file(dir, 'packages/greeter/lib/greeter.rb', <<~RUBY)
        class Greeter
          def self.hello = 'Hello from Boxwerk!'
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts Greeter::Greeter.hello
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "basic_run: exit status"
      assert_match /Hello from Boxwerk!/, out, "basic_run: output"
    end
  end

  def test_dependency_access
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/math'])
      create_package(dir, 'math')
      write_file(dir, 'packages/math/lib/calc.rb', <<~RUBY)
        class Calc
          def self.add(a, b) = a + b
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        result = Math::Calc.add(3, 4)
        puts "Result: \#{result}"
        exit(result == 7 ? 0 : 1)
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "dependency_access: exit status"
      assert_match /Result: 7/, out, "dependency_access: output"
    end
  end

  def test_transitive_blocked
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/a'])
      create_package(dir, 'a', dependencies: ['packages/b'])
      create_package(dir, 'b')
      write_file(dir, 'packages/a/lib/class_a.rb', "class ClassA; end\n")
      write_file(dir, 'packages/b/lib/class_b.rb', "class ClassB; end\n")
      write_file(dir, 'app.rb', <<~RUBY)
        begin
          B::ClassB
          puts "FAIL: transitive dependency was accessible"
          exit 1
        rescue NameError
          puts "PASS: transitive dependency blocked"
          exit 0
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "transitive_blocked: exit status"
      assert_match /PASS/, out, "transitive_blocked: output"
    end
  end

  def test_privacy_enforcement
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/secure'])
      create_package(dir, 'secure', enforce_privacy: true)

      pub_dir = File.join(dir, 'packages', 'secure', 'app', 'public')
      FileUtils.mkdir_p(pub_dir)
      write_file(dir, 'packages/secure/app/public/api.rb', <<~RUBY)
        class Api
          def self.call = 'public api'
        end
      RUBY
      write_file(dir, 'packages/secure/lib/internal.rb', <<~RUBY)
        class Internal
          def self.secret = 'should not see this'
        end
      RUBY

      write_file(dir, 'app.rb', <<~RUBY)
        # Public constant should work
        puts Secure::Api.call

        # Private constant should raise
        begin
          Secure::Internal
          puts "FAIL: private constant accessible"
          exit 1
        rescue NameError => e
          if e.message.include?('Privacy violation')
            puts "PASS: privacy enforced"
            exit 0
          else
            puts "FAIL: wrong error: \#{e.message}"
            exit 1
          end
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "privacy_enforcement: exit status"
      assert_match /public api/, out, "privacy_enforcement: public access"
      assert_match /PASS/, out, "privacy_enforcement: privacy block"
    end
  end

  def test_version_command
    out, status = run_boxwerk(Dir.pwd, 'version')
    assert_equal 0, status.exitstatus, "version: exit status"
    assert_match /boxwerk \d+\.\d+\.\d+/, out, "version: output format"
  end

  def test_info_command
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/core'])
      create_package(dir, 'core')

      out, status = run_boxwerk(dir, 'info')
      assert_equal 0, status.exitstatus, "info: exit status"
      assert_match /Root:/, out, "info: shows root"
      assert_match /Packages:/, out, "info: shows count"
    end
  end

  def test_help_command
    out, status = run_boxwerk(Dir.pwd, 'help')
    assert_equal 0, status.exitstatus, "help: exit status"
    assert_match /Usage:/, out, "help: shows usage"
    assert_match /Commands:/, out, "help: shows commands"
  end

  def test_missing_script_error
    out, status = run_boxwerk(Dir.pwd, 'run')
    assert_equal 1, status.exitstatus, "missing_script: exit status"
    assert_match /No script specified/, out, "missing_script: error message"
  end

  def test_nonexistent_script_error
    out, status = run_boxwerk(Dir.pwd, 'run', 'nonexistent.rb')
    assert_equal 1, status.exitstatus, "nonexistent_script: exit status"
    assert_match /Script not found/, out, "nonexistent_script: error message"
  end

  def test_missing_package_yml_error
    Dir.mktmpdir do |dir|
      write_file(dir, 'app.rb', "puts 'hello'\n")
      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 1, status.exitstatus, "missing_package_yml: exit status"
      assert_match /package\.yml/, out, "missing_package_yml: mentions package.yml"
    end
  end

  def test_layer_violation_at_boot
    with_project do |dir|
      write_file(dir, 'packwerk.yml', YAML.dump('layers' => %w[feature utility]))
      create_root_package(dir, dependencies: %w[packages/feat packages/util])
      create_package(dir, 'feat', layer: 'feature')
      create_package(dir, 'util', layer: 'utility', dependencies: ['packages/feat'],
                     enforce_layers: true)
      write_file(dir, 'packages/feat/lib/feat.rb', "class Feat; end\n")
      write_file(dir, 'packages/util/lib/util_class.rb', "class UtilClass; end\n")
      write_file(dir, 'app.rb', "puts 'should not reach here'\n")

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 1, status.exitstatus, "layer_violation: exit status"
      assert_match /cannot depend on/, out, "layer_violation: error message"
    end
  end

  def test_visibility_enforcement
    with_project do |dir|
      create_root_package(dir, dependencies: %w[packages/secret packages/allowed])

      create_package(dir, 'secret', enforce_visibility: true,
                     visible_to: ['packages/allowed'])
      write_file(dir, 'packages/secret/lib/hidden.rb', <<~RUBY)
        class Hidden
          def self.value = 'secret'
        end
      RUBY

      create_package(dir, 'allowed', dependencies: ['packages/secret'])
      write_file(dir, 'packages/allowed/lib/viewer.rb', "class Viewer; end\n")

      write_file(dir, 'app.rb', <<~RUBY)
        # Root is NOT in visible_to, so Secret namespace should not exist
        begin
          Secret::Hidden
          puts "FAIL: root can see Secret"
          exit 1
        rescue NameError
          puts "PASS: Secret not visible to root"
          exit 0
        end
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "visibility: exit status"
      assert_match /PASS/, out, "visibility: blocked"
    end
  end

  def test_nested_constants
    with_project do |dir|
      create_root_package(dir, dependencies: ['packages/api'])
      create_package(dir, 'api')
      FileUtils.mkdir_p(File.join(dir, 'packages', 'api', 'lib', 'v2'))
      write_file(dir, 'packages/api/lib/v2/endpoint.rb', <<~RUBY)
        module V2
          class Endpoint
            def self.path = '/api/v2'
          end
        end
      RUBY
      write_file(dir, 'app.rb', <<~RUBY)
        puts Api::V2::Endpoint.path
      RUBY

      out, status = run_boxwerk(dir, 'run', 'app.rb')
      assert_equal 0, status.exitstatus, "nested_constants: exit status"
      assert_match %r{/api/v2}, out, "nested_constants: output"
    end
  end

  def test_unknown_command_error
    out, status = run_boxwerk(Dir.pwd, 'foobar')
    assert_equal 1, status.exitstatus, "unknown_command: exit status"
    assert_match /Unknown command/, out, "unknown_command: error message"
  end

  # --- Helpers ---

  def with_project
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  def run_boxwerk(dir, *args)
    env = { 'RUBY_BOX' => '1', 'BUNDLE_GEMFILE' => File.expand_path('../../Gemfile', __dir__) }
    cmd = ['ruby', @boxwerk_bin, *args]
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: dir)
    [stdout + stderr, status]
  end

  def create_root_package(dir, dependencies: [])
    content = { 'enforce_dependencies' => true }
    content['dependencies'] = dependencies if dependencies.any?
    File.write(File.join(dir, 'package.yml'), YAML.dump(content))
  end

  def create_package(dir, name, dependencies: nil, enforce_privacy: false,
                     enforce_visibility: false, visible_to: nil,
                     enforce_layers: false, layer: nil)
    pkg_dir = File.join(dir, 'packages', name)
    FileUtils.mkdir_p(File.join(pkg_dir, 'lib'))
    content = { 'enforce_dependencies' => true }
    content['dependencies'] = dependencies if dependencies
    content['enforce_privacy'] = true if enforce_privacy
    content['enforce_visibility'] = true if enforce_visibility
    content['visible_to'] = visible_to if visible_to
    content['enforce_layers'] = true if enforce_layers
    content['layer'] = layer if layer
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
end

E2ERunner.new.run_all
