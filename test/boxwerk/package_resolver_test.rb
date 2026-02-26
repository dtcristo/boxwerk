# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class PackageResolverTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_discovers_root_package
      create_package(@tmpdir)

      resolver = PackageResolver.new(@tmpdir)

      assert resolver.root
      assert resolver.root.root?
    end

    def test_discovers_dependency_packages
      util_dir = create_package_dir('util')
      create_package(util_dir)

      create_package(@tmpdir, dependencies: ['packs/util'])

      resolver = PackageResolver.new(@tmpdir)

      assert_equal 2, resolver.packages.size
      assert resolver.packages.key?('.')
      assert resolver.packages.key?('packs/util')
    end

    def test_topological_order_dependencies_first
      util_dir = create_package_dir('util')
      create_package(util_dir)

      create_package(@tmpdir, dependencies: ['packs/util'])

      resolver = PackageResolver.new(@tmpdir)
      order = resolver.topological_order

      util_index = order.index { |p| p.name == 'packs/util' }
      root_index = order.index { |p| p.root? }
      assert util_index < root_index
    end

    def test_topological_order_transitive
      util_dir = create_package_dir('util')
      create_package(util_dir)

      finance_dir = create_package_dir('finance')
      create_package(finance_dir, dependencies: ['packs/util'])

      create_package(@tmpdir, dependencies: ['packs/finance'])

      resolver = PackageResolver.new(@tmpdir)
      order = resolver.topological_order

      util_index = order.index { |p| p.name == 'packs/util' }
      finance_index = order.index { |p| p.name == 'packs/finance' }
      root_index = order.index { |p| p.root? }

      assert util_index < finance_index
      assert finance_index < root_index
    end

    def test_circular_dependency_detection
      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/b'])

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/a'])

      create_package(@tmpdir, dependencies: ['packs/a'])

      assert_raises(RuntimeError) { PackageResolver.new(@tmpdir) }
    end

    def test_namespace_for_derives_module_name
      assert_equal 'Finance', PackageResolver.namespace_for('packs/finance')
      assert_equal 'TaxCalc', PackageResolver.namespace_for('packs/tax_calc')
      assert_nil PackageResolver.namespace_for('.')
    end

    def test_direct_dependencies_returns_package_objects
      util_dir = create_package_dir('util')
      create_package(util_dir)

      logger_dir = create_package_dir('logger')
      create_package(logger_dir)

      create_package(@tmpdir, dependencies: %w[packs/util packs/logger])

      resolver = PackageResolver.new(@tmpdir)
      deps = resolver.direct_dependencies(resolver.root)

      assert_equal 2, deps.size
      dep_names = deps.map(&:name).sort
      assert_includes dep_names, 'packs/logger'
      assert_includes dep_names, 'packs/util'
    end

    def test_diamond_dependency
      c_dir = create_package_dir('c')
      create_package(c_dir)

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/c'])

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/c'])

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      resolver = PackageResolver.new(@tmpdir)
      order = resolver.topological_order

      c_index = order.index { |p| p.name == 'packs/c' }
      a_index = order.index { |p| p.name == 'packs/a' }
      b_index = order.index { |p| p.name == 'packs/b' }

      assert c_index < a_index
      assert c_index < b_index
    end

    private

    def create_package_dir(name)
      dir = File.join(@tmpdir, 'packs', name)
      FileUtils.mkdir_p(File.join(dir, 'lib'))
      dir
    end

    def create_package(path, dependencies: nil, enforce: true)
      content = {}
      content['enforce_dependencies'] = enforce
      content['dependencies'] = dependencies if dependencies

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
