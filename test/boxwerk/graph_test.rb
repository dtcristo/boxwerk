# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class GraphTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_graph_with_single_root_package
      create_package(@tmpdir, exports: ['App'])

      graph = Graph.new(@tmpdir)

      assert_equal 1, graph.packages.size
      assert graph.packages.key?('root')
      assert_equal graph.root, graph.packages['root']
    end

    def test_graph_with_dependencies
      # Create util package
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      # Create logger package
      logger_dir = create_package_dir('logger')
      create_package(logger_dir, exports: ['Log'])

      # Create root package that imports both
      create_package(@tmpdir, imports: %w[packages/util packages/logger])

      graph = Graph.new(@tmpdir)

      assert_equal 3, graph.packages.size
      assert graph.packages.key?('root')
      assert graph.packages.key?('util')
      assert graph.packages.key?('logger')
    end

    def test_topological_order_simple
      # Create util package (no dependencies)
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      # Create root package that imports util
      create_package(@tmpdir, imports: ['packages/util'])

      graph = Graph.new(@tmpdir)
      order = graph.topological_order

      assert_equal 2, order.size

      # Util should come before root
      util_index = order.index { |p| p.name == 'util' }
      root_index = order.index { |p| p.name == 'root' }
      assert util_index < root_index
    end

    def test_topological_order_transitive
      # Create util package (no dependencies)
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      # Create finance package (depends on util)
      finance_dir = create_package_dir('finance')
      create_package(
        finance_dir,
        exports: ['Invoice'],
        imports: ['packages/util'],
      )

      # Create root package (depends on finance)
      create_package(@tmpdir, imports: ['packages/finance'])

      graph = Graph.new(@tmpdir)
      order = graph.topological_order

      assert_equal 3, order.size

      # Util should come first, then finance, then root
      util_index = order.index { |p| p.name == 'util' }
      finance_index = order.index { |p| p.name == 'finance' }
      root_index = order.index { |p| p.name == 'root' }

      assert util_index < finance_index
      assert finance_index < root_index
    end

    def test_topological_order_multiple_dependencies
      # Create util package
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      # Create logger package
      logger_dir = create_package_dir('logger')
      create_package(logger_dir, exports: ['Log'])

      # Create finance package (depends on both util and logger)
      finance_dir = create_package_dir('finance')
      create_package(
        finance_dir,
        exports: ['Invoice'],
        imports: %w[packages/util packages/logger],
      )

      # Create root package (depends on finance)
      create_package(@tmpdir, imports: ['packages/finance'])

      graph = Graph.new(@tmpdir)
      order = graph.topological_order

      assert_equal 4, order.size

      # Util and logger should come before finance
      util_index = order.index { |p| p.name == 'util' }
      logger_index = order.index { |p| p.name == 'logger' }
      finance_index = order.index { |p| p.name == 'finance' }
      root_index = order.index { |p| p.name == 'root' }

      assert util_index < finance_index
      assert logger_index < finance_index
      assert finance_index < root_index
    end

    def test_circular_dependency_detection_direct
      # Create util package that depends on logger
      util_dir = create_package_dir('util')
      create_package(
        util_dir,
        exports: ['Calculator'],
        imports: ['packages/logger'],
      )

      # Create logger package that depends on util (circular!)
      logger_dir = create_package_dir('logger')
      create_package(logger_dir, exports: ['Log'], imports: ['packages/util'])

      # Create root package
      create_package(@tmpdir, imports: ['packages/util'])

      assert_raises(RuntimeError) { Graph.new(@tmpdir) }
    end

    def test_circular_dependency_detection_indirect
      # Create a -> b -> c -> a cycle
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['A'], imports: ['packages/b'])

      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['B'], imports: ['packages/c'])

      c_dir = create_package_dir('c')
      create_package(c_dir, exports: ['C'], imports: ['packages/a'])

      create_package(@tmpdir, imports: ['packages/a'])

      assert_raises(RuntimeError) { Graph.new(@tmpdir) }
    end

    def test_package_not_found
      # Root imports non-existent package
      create_package(@tmpdir, imports: ['packages/nonexistent'])

      error = assert_raises(RuntimeError) { Graph.new(@tmpdir) }

      assert_match(/nonexistent/, error.message)
    end

    def test_root_package_accessor
      create_package(@tmpdir, exports: ['App'])

      graph = Graph.new(@tmpdir)

      assert_equal 'root', graph.root.name
      assert_equal @tmpdir, graph.root.path
    end

    def test_packages_hash_accessor
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      create_package(@tmpdir, imports: ['packages/util'])

      graph = Graph.new(@tmpdir)

      assert_instance_of Hash, graph.packages
      assert_equal 2, graph.packages.size
      assert_instance_of Package, graph.packages['root']
      assert_instance_of Package, graph.packages['util']
    end

    def test_diamond_dependency
      # Create a diamond: root -> [a, b], a -> c, b -> c
      c_dir = create_package_dir('c')
      create_package(c_dir, exports: ['C'])

      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['A'], imports: ['packages/c'])

      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['B'], imports: ['packages/c'])

      create_package(@tmpdir, imports: %w[packages/a packages/b])

      graph = Graph.new(@tmpdir)
      order = graph.topological_order

      # C should come before both A and B
      c_index = order.index { |p| p.name == 'c' }
      a_index = order.index { |p| p.name == 'a' }
      b_index = order.index { |p| p.name == 'b' }
      root_index = order.index { |p| p.name == 'root' }

      assert c_index < a_index
      assert c_index < b_index
      assert a_index < root_index
      assert b_index < root_index
    end

    def test_import_with_alias_syntax
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      create_package(@tmpdir, imports: [{ 'packages/util' => 'Calc' }])

      graph = Graph.new(@tmpdir)

      assert_equal 2, graph.packages.size
      assert graph.packages.key?('util')
    end

    def test_import_with_selective_syntax
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: %w[Calculator Geometry])

      create_package(@tmpdir, imports: [{ 'packages/util' => ['Calculator'] }])

      graph = Graph.new(@tmpdir)

      assert_equal 2, graph.packages.size
      assert graph.packages.key?('util')
    end

    def test_import_with_rename_syntax
      util_dir = create_package_dir('util')
      create_package(util_dir, exports: ['Calculator'])

      create_package(
        @tmpdir,
        imports: [{ 'packages/util' => { 'Calculator' => 'Calc' } }],
      )

      graph = Graph.new(@tmpdir)

      assert_equal 2, graph.packages.size
      assert graph.packages.key?('util')
    end

    private

    def create_package_dir(name)
      dir = File.join(@tmpdir, 'packages', name)
      FileUtils.mkdir_p(File.join(dir, 'lib'))
      dir
    end

    def create_package(path, exports: nil, imports: nil)
      content = {}
      content['exports'] = exports if exports
      content['imports'] = imports if imports

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
