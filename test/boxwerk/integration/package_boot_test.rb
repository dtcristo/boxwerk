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

    def test_root_boot_script_runs_in_package_box_not_root_box
      a_dir = create_package_dir('a')
      create_package(a_dir)

      create_package(@tmpdir, dependencies: ['packs/a'])
      File.write(File.join(@tmpdir, 'boot.rb'), "ROOT_BOOT_RAN = true\n")

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      # Ran in the root package box
      assert root_box.eval('ROOT_BOOT_RAN')
      # NOT in the Ruby root box
      refute Ruby::Box.root.eval('defined?(ROOT_BOOT_RAN)')
    end

    def test_root_boot_dependencies_accessible_after_boot
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])
      File.write(File.join(@tmpdir, 'boot.rb'), "ROOT_BOOT_RAN = true\n")

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert root_box.eval('ROOT_BOOT_RAN')
      assert_equal 'from_a', root_box.eval('ClassA.value')
    end

    def test_root_boot_configures_additional_autoload_dirs
      services_dir = File.join(@tmpdir, 'services')
      FileUtils.mkdir_p(services_dir)
      File.write(
        File.join(services_dir, 'root_service.rb'),
        "class RootService\n  def self.value = 'root_svc'\nend\n",
      )

      File.write(
        File.join(@tmpdir, 'boot.rb'),
        "BOXWERK_CONFIG[:autoload_dirs] << 'services'\n",
      )

      create_package(@tmpdir)

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'root_svc', root_box.eval('RootService.value')
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

    def test_boxwerk_package_available_in_boot
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )
      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOOT_PKG = Boxwerk.package\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_instance_of Boxwerk::PackageContext, a_box.eval('BOOT_PKG')
    end

    def test_boxwerk_package_name
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )
      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOOT_PKG_NAME = Boxwerk.package.name\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'packs/a', a_box.eval('BOOT_PKG_NAME')
    end

    def test_boxwerk_package_root
      create_package(@tmpdir)
      File.write(
        File.join(@tmpdir, 'boot.rb'),
        "BOOT_IS_ROOT = Boxwerk.package.root?\n",
      )

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert root_box.eval('BOOT_IS_ROOT')
    end

    def test_boxwerk_package_config_frozen
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )
      File.write(
        File.join(a_dir, 'boot.rb'),
        "BOOT_CONFIG_FROZEN = Boxwerk.package.config.frozen?\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert a_box.eval('BOOT_CONFIG_FROZEN')
    end

    def test_boxwerk_package_autoloader_push_dir
      a_dir = create_package_dir('a')
      create_package(a_dir)

      models_dir = File.join(a_dir, 'models')
      FileUtils.mkdir_p(models_dir)
      File.write(
        File.join(models_dir, 'gadget.rb'),
        "class Gadget\n  def self.value = 'gadget'\nend\n",
      )

      File.write(
        File.join(a_dir, 'boot.rb'),
        "Boxwerk.package.autoloader.push_dir('models')\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'gadget', a_box.eval('Gadget.value')
    end

    def test_boxwerk_package_autoloader_collapse
      a_dir = create_package_dir('a')
      create_package(a_dir)

      concerns_dir = File.join(a_dir, 'lib', 'concerns')
      FileUtils.mkdir_p(concerns_dir)
      File.write(
        File.join(concerns_dir, 'sortable.rb'),
        "module Sortable\n  def self.value = 'sortable'\nend\n",
      )

      File.write(
        File.join(a_dir, 'boot.rb'),
        "Boxwerk.package.autoloader.collapse('lib/concerns')\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert_equal 'sortable', a_box.eval('Sortable.value')
    end

    def test_boxwerk_package_constant_in_box
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )
      File.write(File.join(a_dir, 'boot.rb'), "\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      pkg = a_box.eval('BOXWERK_PACKAGE')
      assert_instance_of Boxwerk::PackageContext, pkg
      assert_equal 'packs/a', pkg.name
    end

    def test_boxwerk_package_nil_outside_boot
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )
      File.write(File.join(a_dir, 'boot.rb'), "\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      boot_system

      assert_nil Boxwerk.package
    end
  end
end
