# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class SetupTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset
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

      Setup.reset

      refute Setup.booted?
      assert_nil Setup.resolver
      assert_nil Setup.box_manager
    end

    def test_run_executes_boot_script
      create_package(@tmpdir)
      File.write(File.join(@tmpdir, 'boot.rb'), "$BOXWERK_BOOT_TEST = true\n")

      Setup.run(start_dir: @tmpdir)

      assert Ruby::Box.root.eval('$BOXWERK_BOOT_TEST')
    end

    def test_run_autoloads_boot_directory
      create_package(@tmpdir)
      boot_dir = File.join(@tmpdir, 'boot')
      FileUtils.mkdir_p(boot_dir)
      File.write(
        File.join(boot_dir, 'boot_helper.rb'),
        "module BootHelper; VALUE = 42; end\n",
      )

      Setup.run(start_dir: @tmpdir)

      assert_equal 42, Ruby::Box.root.eval('BootHelper::VALUE')
    end

    def test_run_works_without_boot_script
      create_package(@tmpdir)

      result = Setup.run(start_dir: @tmpdir)

      assert Setup.booted?
      assert_instance_of PackageResolver, result[:resolver]
    end

    private

    def create_package(path, dependencies: nil)
      content = { 'enforce_dependencies' => true }
      content['dependencies'] = dependencies if dependencies

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
