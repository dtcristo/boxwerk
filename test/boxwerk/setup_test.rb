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

    def test_run_with_implicit_root
      # No package.yml or boxwerk.yml — CWD becomes implicit root
      result = Setup.run(start_dir: @tmpdir)

      assert Setup.booted?
      assert_equal '.', result[:resolver].root.name
      refute result[:resolver].root.enforce_dependencies?
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

    def test_run_executes_global_boot_script
      create_package(@tmpdir)
      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'boot.rb'),
        "$BOXWERK_BOOT_TEST = true\n",
      )

      Setup.run(start_dir: @tmpdir)

      assert Ruby::Box.root.eval('$BOXWERK_BOOT_TEST')
    end

    def test_run_autoloads_global_directory
      create_package(@tmpdir)
      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'global_helper.rb'),
        "module GlobalHelper; VALUE = 42; end\n",
      )

      Setup.run(start_dir: @tmpdir)

      assert_equal 42, Ruby::Box.root.eval('GlobalHelper::VALUE')
    end

    def test_global_files_all_eagerly_required
      create_package(@tmpdir)
      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'alpha.rb'),
        "module Alpha; VALUE = 1; end\n",
      )
      File.write(
        File.join(global_dir, 'beta.rb'),
        "module Beta; VALUE = 2; end\n",
      )
      File.write(
        File.join(global_dir, 'gamma.rb'),
        "module Gamma; VALUE = 3; end\n",
      )

      Setup.run(start_dir: @tmpdir)

      assert_equal 1, Ruby::Box.root.eval('Alpha::VALUE')
      assert_equal 2, Ruby::Box.root.eval('Beta::VALUE')
      assert_equal 3, Ruby::Box.root.eval('Gamma::VALUE')
    end

    def test_global_constants_available_in_child_packages
      # Create a child package
      packs_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(File.join(packs_dir, 'lib'))
      create_package(packs_dir)

      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'global_helper.rb'),
        "module GlobalHelper; VALUE = 42; end\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = Setup.run(start_dir: @tmpdir)
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 42, a_box.eval('GlobalHelper::VALUE')
    end

    def test_run_works_without_global_boot
      create_package(@tmpdir)

      result = Setup.run(start_dir: @tmpdir)

      assert Setup.booted?
      assert_instance_of PackageResolver, result[:resolver]
    end

    def test_eager_load_global_false_skips_global_files
      create_package(@tmpdir)
      File.write(
        File.join(@tmpdir, 'boxwerk.yml'),
        YAML.dump('eager_load_global' => false),
      )
      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'eager_test.rb'),
        "module EagerTest; VALUE = 99; end\n",
      )

      Setup.run(start_dir: @tmpdir)

      # Global file should NOT be eagerly loaded
      refute Ruby::Box.root.eval('defined?(EagerTest)')
    end

    def test_eager_load_global_false_still_runs_boot
      create_package(@tmpdir)
      File.write(
        File.join(@tmpdir, 'boxwerk.yml'),
        YAML.dump('eager_load_global' => false),
      )
      global_dir = File.join(@tmpdir, 'global')
      FileUtils.mkdir_p(global_dir)
      File.write(
        File.join(global_dir, 'boot.rb'),
        "$EAGER_BOOT_TEST = true\n",
      )

      Setup.run(start_dir: @tmpdir)

      # global/boot.rb should STILL run
      assert Ruby::Box.root.eval('$EAGER_BOOT_TEST')
    end

    def test_eager_load_packages_true_loads_constants
      packs_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(File.join(packs_dir, 'lib'))
      create_package(packs_dir)
      File.write(
        File.join(packs_dir, 'lib', 'eager_pkg.rb'),
        "class EagerPkg; VALUE = 42; end\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])
      File.write(
        File.join(@tmpdir, 'boxwerk.yml'),
        YAML.dump('eager_load_packages' => true),
      )

      result = Setup.run(start_dir: @tmpdir)
      a_box = result[:box_manager].boxes['packs/a']

      # Constant should be defined (eager-loaded, not just autoloaded)
      assert a_box.eval('defined?(EagerPkg)')
    end

    private

    def create_package(path, dependencies: nil)
      content = { 'enforce_dependencies' => true }
      content['dependencies'] = dependencies if dependencies

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
