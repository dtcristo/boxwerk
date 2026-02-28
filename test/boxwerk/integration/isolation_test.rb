# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for core box isolation: direct constant access, transitive prevention,
  # sibling isolation, dependency chains, diamond deps, constant caching.
  class IsolationTest < Minitest::Test
    include IntegrationTestHelper

    def test_package_can_access_dependency_constants_directly
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'from_a'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'from_a', root_box.eval('ClassA.value')
    end

    def test_package_cannot_access_non_dependency_constants
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'ClassA', root_box.eval('ClassA.name')
      assert_raises(NameError) { root_box.eval('_ = ClassB') }
    end

    def test_transitive_dependencies_not_accessible
      c_dir = create_package_dir('c')
      create_package(c_dir)
      File.write(File.join(c_dir, 'lib', 'class_c.rb'), "class ClassC\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/c'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    ClassC.name + '_via_b'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/b'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'ClassB', root_box.eval('ClassB.name')
      assert_raises(NameError) { root_box.eval('_ = ClassC') }
    end

    def test_sibling_packages_isolated
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      a_box = result[:box_manager].boxes['packs/a']
      b_box = result[:box_manager].boxes['packs/b']

      refute a_box.eval('defined?(ClassB)'), 'Package A should not see ClassB'
      refute b_box.eval('defined?(ClassA)'), 'Package B should not see ClassA'
    end

    def test_complex_chain_isolation
      d_dir = create_package_dir('d')
      create_package(d_dir)
      File.write(File.join(d_dir, 'lib', 'class_d.rb'), "class ClassD\nend\n")

      c_dir = create_package_dir('c')
      create_package(c_dir, dependencies: ['packs/d'])
      File.write(File.join(c_dir, 'lib', 'class_c.rb'), "class ClassC\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/c'])
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/b'])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert a_box.eval(
               'begin; _ = ClassB; true; rescue NameError; false; end',
             ),
             'A should have ClassB'
      refute a_box.eval(
               'begin; _ = ClassC; true; rescue NameError; false; end',
             ),
             'A should not have ClassC'
      refute a_box.eval(
               'begin; _ = ClassD; true; rescue NameError; false; end',
             ),
             'A should not have ClassD'
    end

    def test_diamond_dependency_isolation
      d_dir = create_package_dir('d')
      create_package(d_dir)
      File.write(
        File.join(d_dir, 'lib', 'class_d.rb'),
        "class ClassD\n  def self.value\n    'from_d'\n  end\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/d'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    ClassD.value + '_via_b'\n  end\nend\n",
      )

      c_dir = create_package_dir('c')
      create_package(c_dir, dependencies: ['packs/d'])
      File.write(
        File.join(c_dir, 'lib', 'class_c.rb'),
        "class ClassC\n  def self.value\n    ClassD.value + '_via_c'\n  end\nend\n",
      )

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: %w[packs/b packs/c])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      a_box = result[:box_manager].boxes['packs/a']

      assert a_box.eval(
               'begin; _ = ClassB; true; rescue NameError; false; end',
             ),
             'A should have ClassB'
      assert a_box.eval(
               'begin; _ = ClassC; true; rescue NameError; false; end',
             ),
             'A should have ClassC'
      refute a_box.eval(
               'begin; _ = ClassD; true; rescue NameError; false; end',
             ),
             'A should not have ClassD'
    end

    def test_constant_caching
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'cached'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'cached', root_box.eval('ClassA.value')
      assert_equal 'cached', root_box.eval('ClassA.value')
    end

    def test_multiple_constants_from_same_package
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'foo.rb'),
        "class Foo\n  def self.name = 'foo'\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'bar.rb'),
        "class Bar\n  def self.name = 'bar'\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'baz.rb'),
        "class Baz\n  def self.name = 'baz'\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'foo', root_box.eval('Foo.name')
      assert_equal 'bar', root_box.eval('Bar.name')
      assert_equal 'baz', root_box.eval('Baz.name')
    end

    def test_relaxed_deps_searches_all_packages
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value = 'from_a'\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value = 'from_b'\nend\n",
      )

      # Root does NOT enforce dependencies and has NO explicit deps
      File.write(
        File.join(@tmpdir, 'package.yml'),
        YAML.dump('enforce_dependencies' => false),
      )

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      # Should be able to access both packages without declaring deps
      assert_equal 'from_a', root_box.eval('ClassA.value')
      assert_equal 'from_b', root_box.eval('ClassB.value')
    end

    def test_relaxed_deps_explicit_deps_searched_first
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'shared.rb'),
        "class Shared\n  def self.value = 'from_a'\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'shared.rb'),
        "class Shared\n  def self.value = 'from_b'\nend\n",
      )

      # Root has explicit dep on b, but does not enforce — b searched first
      File.write(
        File.join(@tmpdir, 'package.yml'),
        YAML.dump(
          'enforce_dependencies' => false,
          'dependencies' => ['packs/b'],
        ),
      )

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'from_b', root_box.eval('Shared.value')
    end
  end
end
