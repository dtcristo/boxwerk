# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  # Integration test that explicitly verifies content isolation between boxes/packages
  class IntegrationTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset!
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset!
    end

    def test_package_cannot_access_non_imported_constants
      # Create package A with exported constant
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['ClassA'])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'from_a'\n  end\nend\n",
      )

      # Create package B with exported constant (no import of A)
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.try_access_a\n    defined?(ClassA) ? ClassA.value : nil\n  end\nend\n",
      )

      # Root imports both A and B
      create_package(@tmpdir, imports: %w[packages/a packages/b])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      b_package = registry.get('b')

      # Package B should NOT have access to ClassA (it didn't import it)
      result = b_package.box.eval('ClassB.try_access_a')
      assert_nil result, 'Package B should not have access to ClassA'

      # Verify ClassA is NOT defined in package B's box
      has_class_a = b_package.box.eval('defined?(ClassA)')
      assert_nil has_class_a, 'ClassA should not be defined in package B box'

      # Root should have access to both (single export optimization: A and B are the classes directly)
      root_package = registry.get('root')
      assert root_package.box.eval('defined?(A)')
      assert root_package.box.eval('defined?(B)')
      assert_equal 'from_a', root_package.box.eval('A.value')
    end

    def test_package_cannot_access_transitive_dependencies
      # Create package C (leaf dependency)
      c_dir = create_package_dir('c')
      create_package(c_dir, exports: ['ClassC'])
      File.write(
        File.join(c_dir, 'lib', 'class_c.rb'),
        "class ClassC\n  def self.value\n    'from_c'\n  end\nend\n",
      )

      # Create package B (imports C)
      # Single export optimization: C will be ClassC directly
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'], imports: ['packages/c'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    C.value + '_via_b'\n  end\nend\n",
      )

      # Create package A (imports B but NOT C)
      # Single export optimization: B will be ClassB directly
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['ClassA'], imports: ['packages/b'])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.use_b\n    B.value\n  end\n  def self.try_access_c\n    defined?(C) ? 'found' : nil\n  end\nend\n",
      )

      # Root imports only A
      create_package(@tmpdir, imports: ['packages/a'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      a_package = registry.get('a')

      # Package A can access B (direct import)
      result = a_package.box.eval('ClassA.use_b')
      assert_equal 'from_c_via_b', result

      # Package A CANNOT access C (transitive dependency)
      result = a_package.box.eval('ClassA.try_access_c')
      assert_nil result,
                 'Package A should not have access to C (transitive dependency)'

      # Root CANNOT access B or C (only imported A)
      root_package = registry.get('root')
      refute root_package.box.eval('defined?(B)'), 'Root should not have B'
      refute root_package.box.eval('defined?(C)'), 'Root should not have C'
    end

    def test_package_cannot_access_non_exported_constants
      # Create package A with one exported and one private constant
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['PublicClass'])
      File.write(
        File.join(a_dir, 'lib', 'public_class.rb'),
        "class PublicClass\n  def self.value\n    'public'\n  end\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'private_class.rb'),
        "class PrivateClass\n  def self.value\n    'private'\n  end\nend\n",
      )

      # Create package B that imports A
      # Single export optimization: A will be PublicClass directly
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'], imports: ['packages/a'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.try_access_private\n    defined?(PrivateClass) ? 'found' : nil\n  end\n  def self.access_public\n    A.value\n  end\nend\n",
      )

      # Root imports B
      create_package(@tmpdir, imports: ['packages/b'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      b_package = registry.get('b')

      # Package B can access the exported PublicClass (imported as A)
      result = b_package.box.eval('ClassB.access_public')
      assert_equal 'public', result

      # Package B CANNOT access the non-exported PrivateClass
      result = b_package.box.eval('ClassB.try_access_private')
      assert_nil result,
                 'Package B should not have access to non-exported PrivateClass'

      # PrivateClass should not exist in B's box at all
      has_private = b_package.box.eval('defined?(PrivateClass)')
      assert_nil has_private, 'PrivateClass should not exist in package B'
    end

    def test_sibling_packages_cannot_access_each_other
      # Create package A
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['ClassA'])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.try_access_b\n    defined?(ClassB) ? 'found' : nil\n  end\n  def self.try_access_b_import\n    defined?(B) ? 'found' : nil\n  end\nend\n",
      )

      # Create package B
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.try_access_a\n    defined?(ClassA) ? 'found' : nil\n  end\n  def self.try_access_a_import\n    defined?(A) ? 'found' : nil\n  end\nend\n",
      )

      # Root imports both (but they don't import each other)
      create_package(@tmpdir, imports: %w[packages/a packages/b])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      a_package = registry.get('a')
      b_package = registry.get('b')

      # Package A cannot see ClassB or B
      result = a_package.box.eval('ClassA.try_access_b')
      assert_nil result, 'Package A should not have access to ClassB'
      result = a_package.box.eval('ClassA.try_access_b_import')
      assert_nil result, 'Package A should not have access to B import'

      # Package B cannot see ClassA or A
      result = b_package.box.eval('ClassB.try_access_a')
      assert_nil result, 'Package B should not have access to ClassA'
      result = b_package.box.eval('ClassB.try_access_a_import')
      assert_nil result, 'Package B should not have access to A import'

      # Root can see both (single export optimization)
      root_package = registry.get('root')
      assert root_package.box.eval('defined?(A)')
      assert root_package.box.eval('defined?(B)')
    end

    def test_selective_import_isolation
      # Create package A with multiple exports
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: %w[ClassA1 ClassA2 ClassA3])
      File.write(
        File.join(a_dir, 'lib', 'classes.rb'),
        "class ClassA1\nend\nclass ClassA2\nend\nclass ClassA3\nend\n",
      )

      # Create package B that selectively imports only ClassA1 and ClassA2
      b_dir = create_package_dir('b')
      create_package(
        b_dir,
        exports: ['ClassB'],
        imports: [{ 'packages/a' => %w[ClassA1 ClassA2] }],
      )
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.has_a1\n    defined?(ClassA1) ? true : false\n  end\n  def self.has_a2\n    defined?(ClassA2) ? true : false\n  end\n  def self.has_a3\n    defined?(ClassA3) ? true : false\n  end\nend\n",
      )

      # Root imports B
      create_package(@tmpdir, imports: ['packages/b'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      b_package = registry.get('b')

      # Package B should have ClassA1 and ClassA2
      assert b_package.box.eval('ClassB.has_a1'),
             'Package B should have ClassA1'
      assert b_package.box.eval('ClassB.has_a2'),
             'Package B should have ClassA2'

      # Package B should NOT have ClassA3 (not in selective import)
      refute b_package.box.eval('ClassB.has_a3'),
             'Package B should not have ClassA3'
    end

    def test_import_rename_does_not_expose_original_name
      # Create package A
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['Calculator'])
      File.write(
        File.join(a_dir, 'lib', 'calculator.rb'),
        "class Calculator\n  def self.add(a, b)\n    a + b\n  end\nend\n",
      )

      # Create package B that renames Calculator to Calc
      b_dir = create_package_dir('b')
      create_package(
        b_dir,
        exports: ['ClassB'],
        imports: [{ 'packages/a' => { 'Calculator' => 'Calc' } }],
      )
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.has_calc\n    defined?(Calc) ? true : false\n  end\n  def self.has_calculator\n    defined?(Calculator) ? true : false\n  end\n  def self.use_calc\n    Calc.add(1, 2)\n  end\nend\n",
      )

      # Root imports B
      create_package(@tmpdir, imports: ['packages/b'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      b_package = registry.get('b')

      # Package B should have Calc (renamed)
      assert b_package.box.eval('ClassB.has_calc'), 'Package B should have Calc'
      assert_equal 3, b_package.box.eval('ClassB.use_calc')

      # Package B should NOT have Calculator (original name)
      refute b_package.box.eval('ClassB.has_calculator'),
             'Package B should not have Calculator (only renamed Calc)'
    end

    def test_namespace_import_does_not_expose_individual_constants
      # Create package A with multiple exports (will use namespace, not single export optimization)
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: %w[ClassA1 ClassA2])
      File.write(
        File.join(a_dir, 'lib', 'classes.rb'),
        "class ClassA1\nend\nclass ClassA2\nend\n",
      )

      # Create package B that imports A as namespace
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'], imports: ['packages/a'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.has_a_namespace\n    defined?(A) ? true : false\n  end\n  def self.has_class_a1_direct\n    defined?(ClassA1) ? true : false\n  end\n  def self.has_class_a2_direct\n    defined?(ClassA2) ? true : false\n  end\n  def self.access_via_namespace\n    A::ClassA1\n  end\nend\n",
      )

      # Root imports B
      create_package(@tmpdir, imports: ['packages/b'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      b_package = registry.get('b')

      # Package B should have A namespace
      assert b_package.box.eval('ClassB.has_a_namespace'),
             'Package B should have A namespace'

      # Package B can access via namespace
      assert b_package.box.eval('ClassB.access_via_namespace')

      # Package B should NOT have direct access to ClassA1 or ClassA2
      refute b_package.box.eval('ClassB.has_class_a1_direct'),
             'Package B should not have direct access to ClassA1'
      refute b_package.box.eval('ClassB.has_class_a2_direct'),
             'Package B should not have direct access to ClassA2'
    end

    def test_complex_multi_package_isolation
      # Create package D (leaf)
      d_dir = create_package_dir('d')
      create_package(d_dir, exports: ['ClassD'])
      File.write(File.join(d_dir, 'lib', 'd.rb'), "class ClassD\nend\n")

      # Create package C (imports D)
      # Single export optimization: D will be ClassD directly
      c_dir = create_package_dir('c')
      create_package(c_dir, exports: ['ClassC'], imports: ['packages/d'])
      File.write(
        File.join(c_dir, 'lib', 'c.rb'),
        "class ClassC\n  def self.has_d\n    defined?(D)\n  end\nend\n",
      )

      # Create package B (imports C, NOT D)
      # Single export optimization: C will be ClassC directly
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'], imports: ['packages/c'])
      File.write(
        File.join(b_dir, 'lib', 'b.rb'),
        "class ClassB\n  def self.has_c\n    defined?(C)\n  end\n  def self.has_d\n    defined?(D)\n  end\nend\n",
      )

      # Create package A (imports B, NOT C or D)
      # Single export optimization: B will be ClassB directly
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['ClassA'], imports: ['packages/b'])
      File.write(
        File.join(a_dir, 'lib', 'a.rb'),
        "class ClassA\n  def self.has_b\n    defined?(B)\n  end\n  def self.has_c\n    defined?(C)\n  end\n  def self.has_d\n    defined?(D)\n  end\nend\n",
      )

      # Root imports A
      create_package(@tmpdir, imports: ['packages/a'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      # Verify isolation at each level
      a_package = registry.get('a')
      assert a_package.box.eval('ClassA.has_b'),
             'A should have B (direct import)'
      refute a_package.box.eval('ClassA.has_c'),
             'A should not have C (transitive)'
      refute a_package.box.eval('ClassA.has_d'),
             'A should not have D (transitive)'

      b_package = registry.get('b')
      assert b_package.box.eval('ClassB.has_c'),
             'B should have C (direct import)'
      refute b_package.box.eval('ClassB.has_d'),
             'B should not have D (transitive)'

      c_package = registry.get('c')
      assert c_package.box.eval('ClassC.has_d'),
             'C should have D (direct import)'

      # Root should only have A (single export optimization)
      root_package = registry.get('root')
      assert root_package.box.eval('defined?(A)'), 'Root should have A'
      refute root_package.box.eval('defined?(B)'), 'Root should not have B'
      refute root_package.box.eval('defined?(C)'), 'Root should not have C'
      refute root_package.box.eval('defined?(D)'), 'Root should not have D'
    end

    def test_root_package_isolation
      # Create package A
      a_dir = create_package_dir('a')
      create_package(a_dir, exports: ['ClassA'])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'from_a'\n  end\nend\n",
      )

      # Root imports A
      create_package(@tmpdir, imports: ['packages/a'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      root_package = registry.get('root')
      a_package = registry.get('a')

      # Root should have access to A (single export optimization)
      assert root_package.box.eval('defined?(A)')
      assert_equal 'from_a', root_package.box.eval('A.value')

      # Root should NOT have access to ClassA directly (it's wrapped as A)
      refute root_package.box.eval('defined?(ClassA)'),
             'Root should not have direct access to ClassA'

      # Package A should have ClassA defined
      assert a_package.box.eval('defined?(ClassA)')
    end

    def test_diamond_dependency_isolation
      # Create package D (shared dependency)
      d_dir = create_package_dir('d')
      create_package(d_dir, exports: ['ClassD'])
      File.write(
        File.join(d_dir, 'lib', 'd.rb'),
        "class ClassD\n  def self.value\n    'from_d'\n  end\nend\n",
      )

      # Create package B (imports D)
      b_dir = create_package_dir('b')
      create_package(b_dir, exports: ['ClassB'], imports: ['packages/d'])
      File.write(
        File.join(b_dir, 'lib', 'b.rb'),
        "class ClassB\n  def self.value\n    D.value + '_via_b'\n  end\nend\n",
      )

      # Create package C (also imports D)
      c_dir = create_package_dir('c')
      create_package(c_dir, exports: ['ClassC'], imports: ['packages/d'])
      File.write(
        File.join(c_dir, 'lib', 'c.rb'),
        "class ClassC\n  def self.value\n    D.value + '_via_c'\n  end\nend\n",
      )

      # Create package A (imports B and C, but NOT D directly)
      a_dir = create_package_dir('a')
      create_package(
        a_dir,
        exports: ['ClassA'],
        imports: %w[packages/b packages/c],
      )
      File.write(
        File.join(a_dir, 'lib', 'a.rb'),
        "class ClassA\n  def self.use_b\n    B.value\n  end\n  def self.use_c\n    C.value\n  end\n  def self.has_d\n    defined?(D)\n  end\nend\n",
      )

      # Root imports A
      create_package(@tmpdir, imports: ['packages/a'])

      # Boot the system
      graph = Graph.new(@tmpdir)
      registry = Registry.new
      Loader.boot_all(graph, registry)

      a_package = registry.get('a')

      # Package A can use B and C
      assert_equal 'from_d_via_b', a_package.box.eval('ClassA.use_b')
      assert_equal 'from_d_via_c', a_package.box.eval('ClassA.use_c')

      # Package A should NOT have direct access to D (even though both B and C import it)
      refute a_package.box.eval('ClassA.has_d'),
             'Package A should not have access to D (transitive through B and C)'
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
