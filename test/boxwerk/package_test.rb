# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class PackageTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_initialization_with_no_config
      pkg = Package.new('test', @tmpdir)

      assert_equal 'test', pkg.name
      assert_equal @tmpdir, pkg.path
      assert_equal [], pkg.exports
      assert_equal [], pkg.imports
      assert_nil pkg.box
      refute pkg.booted?
    end

    def test_loads_exports_and_imports_from_yaml
      create_package_yml(exports: %w[ClassA ClassB], imports: ['packages/math'])

      pkg = Package.new('test', @tmpdir)

      assert_equal %w[ClassA ClassB], pkg.exports
      assert_equal ['packages/math'], pkg.imports
    end

    def test_dependencies_extracts_paths_from_various_import_formats
      create_package_yml(
        imports: [
          'packages/math',
          { 'packages/utils' => 'Tools' },
          { 'packages/logger' => ['Log'] },
        ]
      )

      pkg = Package.new('test', @tmpdir)

      assert_equal %w[packages/math packages/utils packages/logger], pkg.dependencies
    end

    def test_booted_status_changes_with_box
      pkg = Package.new('test', @tmpdir)

      refute pkg.booted?

      pkg.box = Ruby::Box.new

      assert pkg.booted?
    end

    private

    def create_package_yml(exports: nil, imports: nil)
      content = {}
      content['exports'] = exports if exports
      content['imports'] = imports if imports

      File.write(File.join(@tmpdir, 'package.yml'), YAML.dump(content))
    end
  end
end
