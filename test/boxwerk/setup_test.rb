# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class SetupTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset!
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset!
    end

    def test_run_raises_without_package_yml
      error = assert_raises(RuntimeError) { Setup.run(start_dir: @tmpdir) }

      assert_match(/Cannot find package.yml/, error.message)
    end

    def test_run_finds_package_yml_and_boots
      create_package(@tmpdir)

      result = Setup.run(start_dir: @tmpdir)

      assert Setup.booted?
      assert_instance_of PackageResolver, result[:resolver]
      assert_instance_of BoxManager, result[:box_manager]
    end

    def test_run_searches_up_directory_tree
      create_package(@tmpdir)
      nested_dir = File.join(@tmpdir, 'app', 'lib', 'deep')
      FileUtils.mkdir_p(nested_dir)

      result = Setup.run(start_dir: nested_dir)

      assert Setup.booted?
      assert result[:resolver].root
    end

    def test_reset_clears_state
      create_package(@tmpdir)
      Setup.run(start_dir: @tmpdir)

      Setup.reset!

      refute Setup.booted?
      assert_nil Setup.resolver
      assert_nil Setup.box_manager
    end

    private

    def create_package(path, dependencies: nil)
      content = { 'enforce_dependencies' => true }
      content['dependencies'] = dependencies if dependencies

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
