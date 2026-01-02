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

    def test_package_initialization
      pkg = Package.new('test_package', @tmpdir)

      assert_equal 'test_package', pkg.name
      assert_equal @tmpdir, pkg.path
      assert_equal [], pkg.exports
      assert_equal [], pkg.imports
      assert_nil pkg.box
      refute pkg.booted?
    end

    def test_package_with_exports
      create_package_yml(exports: %w[ClassA ClassB])

      pkg = Package.new('test', @tmpdir)

      assert_equal %w[ClassA ClassB], pkg.exports
    end

    def test_package_with_string_import
      create_package_yml(imports: ['packages/math'])

      pkg = Package.new('test', @tmpdir)

      assert_equal ['packages/math'], pkg.imports
    end

    def test_package_with_aliased_import
      create_package_yml(imports: [{ 'packages/math' => 'Calc' }])

      pkg = Package.new('test', @tmpdir)

      assert_equal 1, pkg.imports.size
      assert pkg.imports[0].is_a?(Hash)
      assert_equal 'Calc', pkg.imports[0]['packages/math']
    end

    def test_package_with_selective_import_array
      create_package_yml(imports: [{ 'packages/utils' => %w[Log Metrics] }])

      pkg = Package.new('test', @tmpdir)

      assert_equal 1, pkg.imports.size
      assert pkg.imports[0].is_a?(Hash)
      assert_equal %w[Log Metrics], pkg.imports[0]['packages/utils']
    end

    def test_package_with_selective_import_hash
      create_package_yml(
        imports: [
          { 'packages/billing' => { 'Invoice' => 'Bill', 'Payment' => 'Pay' } },
        ],
      )

      pkg = Package.new('test', @tmpdir)

      assert_equal 1, pkg.imports.size
      assert pkg.imports[0].is_a?(Hash)
      assert pkg.imports[0]['packages/billing'].is_a?(Hash)
      assert_equal 'Bill', pkg.imports[0]['packages/billing']['Invoice']
      assert_equal 'Pay', pkg.imports[0]['packages/billing']['Payment']
    end

    def test_package_with_multiple_import_strategies
      create_package_yml(
        imports: [
          'packages/math',
          { 'packages/utils' => 'Tools' },
          { 'packages/logger' => ['Log'] },
          { 'packages/billing' => { 'Invoice' => 'Bill' } },
        ],
      )

      pkg = Package.new('test', @tmpdir)

      assert_equal 4, pkg.imports.size
      assert_equal 'packages/math', pkg.imports[0]
      assert_equal 'Tools', pkg.imports[1]['packages/utils']
      assert_equal ['Log'], pkg.imports[2]['packages/logger']
      assert_equal 'Bill', pkg.imports[3]['packages/billing']['Invoice']
    end

    def test_dependencies_extraction
      create_package_yml(
        imports: [
          'packages/math',
          { 'packages/utils' => 'Tools' },
          { 'packages/logger' => ['Log'] },
        ],
      )

      pkg = Package.new('test', @tmpdir)
      deps = pkg.dependencies

      assert_equal 3, deps.size
      assert_includes deps, 'packages/math'
      assert_includes deps, 'packages/utils'
      assert_includes deps, 'packages/logger'
    end

    def test_booted_status
      pkg = Package.new('test', @tmpdir)

      refute pkg.booted?

      pkg.box = 'mock_box'

      assert pkg.booted?
    end

    def test_empty_package_yml
      create_package_yml

      pkg = Package.new('test', @tmpdir)

      assert_equal [], pkg.exports
      assert_equal [], pkg.imports
    end

    def test_package_yml_with_only_exports
      create_package_yml(exports: ['OnlyExport'])

      pkg = Package.new('test', @tmpdir)

      assert_equal ['OnlyExport'], pkg.exports
      assert_equal [], pkg.imports
    end

    def test_package_yml_with_only_imports
      create_package_yml(imports: ['packages/dep'])

      pkg = Package.new('test', @tmpdir)

      assert_equal [], pkg.exports
      assert_equal ['packages/dep'], pkg.imports
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
