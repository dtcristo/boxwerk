# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for per-package boot.rb scripts that run in the package box
  # context during boot, before dependency wiring.
  class PackageBootTest < Minitest::Test
    include IntegrationTestHelper

    def test_package_boot_script_runs_in_box
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )
      File.write(File.join(a_dir, 'boot.rb'), "BOOT_RAN = true\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert a_box.eval('BOOT_RAN')
    end

    def test_package_boot_can_access_own_autoloaded_constants
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )
      File.write(File.join(a_dir, 'boot.rb'), "BOOT_VALUE = ClassA.value\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'from_a', a_box.eval('BOOT_VALUE')
    end

    def test_package_boot_configures_additional_autoload_dir
      a_dir = create_package_dir('a')
      create_package(a_dir)

      # Create a models/ directory with a file
      models_dir = File.join(a_dir, 'models')
      FileUtils.mkdir_p(models_dir)
      File.write(
        File.join(models_dir, 'thing.rb'),
        "class Thing\n  def self.value = 'thing'\nend\n",
      )

      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOXWERK_CONFIG[:autoload_dirs] << 'models'\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'thing', a_box.eval('Thing.value')
    end

    def test_package_boot_collapse_dirs
      a_dir = create_package_dir('a')
      create_package(a_dir)

      # Create a concerns/ subdirectory inside lib/
      concerns_dir = File.join(a_dir, 'lib', 'concerns')
      FileUtils.mkdir_p(concerns_dir)
      File.write(
        File.join(concerns_dir, 'taggable.rb'),
        "module Taggable\n  def self.value = 'taggable'\nend\n",
      )

      # Collapse concerns/ so Taggable is at top level, not Concerns::Taggable
      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOXWERK_CONFIG[:collapse_dirs] << 'lib/concerns'\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      # Taggable should be directly accessible (collapsed from Concerns::Taggable)
      assert_equal 'taggable', a_box.eval('Taggable.value')
    end

    def test_package_without_boot_script_works_normally
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'from_a', a_box.eval('ClassA.value')
    end

    def test_additional_autoload_dir_constants_available_to_dependents
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: false)

      models_dir = File.join(a_dir, 'models')
      FileUtils.mkdir_p(models_dir)
      File.write(
        File.join(models_dir, 'widget.rb'),
        "class Widget\n  def self.value = 'widget'\nend\n",
      )

      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOXWERK_CONFIG[:autoload_dirs] << 'models'\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'widget', root_box.eval('Widget.value')
    end
  end
end
