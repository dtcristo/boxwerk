# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  # Integration tests verifying runtime constant isolation using Ruby::Box
  # and const_missing-based resolution from Packwerk dependencies.
  class IntegrationTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset!
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset!
    end

    def test_package_can_access_dependency_constants_via_namespace
      # Create package A with a constant
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'from_a'\n  end\nend\n",
      )

      # Root depends on A
      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Root can access ClassA via A:: namespace
      assert root_box.eval('defined?(A)'), 'Root should have A namespace'
      assert_equal 'from_a', root_box.eval('A::ClassA.value')
    end

    def test_package_cannot_access_non_dependency_constants
      # Create package A
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'from_a'\n  end\nend\n",
      )

      # Create package B (no dependency on A)
      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    'from_b'\n  end\nend\n",
      )

      # Root depends on A only (not B)
      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Root can access A
      assert root_box.eval('defined?(A)'), 'Root should have A namespace'

      # Root cannot access B (not a dependency)
      assert_raises(NameError) { root_box.eval('B') }
    end

    def test_transitive_dependencies_not_accessible
      # Create package C (leaf)
      c_dir = create_package_dir('c')
      create_package(c_dir)
      File.write(
        File.join(c_dir, 'lib', 'class_c.rb'),
        "class ClassC\n  def self.value\n    'from_c'\n  end\nend\n",
      )

      # Create package B (depends on C)
      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packages/c'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    C::ClassC.value + '_via_b'\n  end\nend\n",
      )

      # Root depends on B only (not C)
      create_package(@tmpdir, dependencies: ['packages/b'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Root can access B
      assert root_box.eval('defined?(B)'), 'Root should have B namespace'

      # Root CANNOT access C (transitive dependency)
      assert_raises(NameError) { root_box.eval('C') }
    end

    def test_sibling_packages_isolated
      # Create package A
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )

      # Create package B
      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\nend\n",
      )

      # Root depends on both A and B
      create_package(@tmpdir, dependencies: %w[packages/a packages/b])

      result = boot_system

      a_box = result[:box_manager].boxes['packages/a']
      b_box = result[:box_manager].boxes['packages/b']

      # Package A cannot see B
      refute a_box.eval('defined?(B)'), 'Package A should not see B'
      refute a_box.eval('defined?(ClassB)'), 'Package A should not see ClassB'

      # Package B cannot see A
      refute b_box.eval('defined?(A)'), 'Package B should not see A'
      refute b_box.eval('defined?(ClassA)'), 'Package B should not see ClassA'
    end

    def test_complex_chain_isolation
      # D -> C -> B -> A (each only depends on the next)
      d_dir = create_package_dir('d')
      create_package(d_dir)
      File.write(File.join(d_dir, 'lib', 'class_d.rb'), "class ClassD\nend\n")

      c_dir = create_package_dir('c')
      create_package(c_dir, dependencies: ['packages/d'])
      File.write(File.join(c_dir, 'lib', 'class_c.rb'), "class ClassC\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packages/c'])
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packages/b'])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      a_box = result[:box_manager].boxes['packages/a']

      # A can access B (direct dependency)
      assert a_box.eval('defined?(B)'), 'A should have B'

      # A cannot access C or D (transitive)
      refute a_box.eval('defined?(C)'), 'A should not have C'
      refute a_box.eval('defined?(D)'), 'A should not have D'
    end

    def test_diamond_dependency_isolation
      # D is shared: B->D, C->D; A->[B,C] but NOT D
      d_dir = create_package_dir('d')
      create_package(d_dir)
      File.write(
        File.join(d_dir, 'lib', 'class_d.rb'),
        "class ClassD\n  def self.value\n    'from_d'\n  end\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packages/d'])
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    D::ClassD.value + '_via_b'\n  end\nend\n",
      )

      c_dir = create_package_dir('c')
      create_package(c_dir, dependencies: ['packages/d'])
      File.write(
        File.join(c_dir, 'lib', 'class_c.rb'),
        "class ClassC\n  def self.value\n    D::ClassD.value + '_via_c'\n  end\nend\n",
      )

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: %w[packages/b packages/c])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      a_box = result[:box_manager].boxes['packages/a']

      # A can access B and C
      assert a_box.eval('defined?(B)'), 'A should have B'
      assert a_box.eval('defined?(C)'), 'A should have C'

      # A CANNOT access D (transitive through both B and C)
      refute a_box.eval('defined?(D)'), 'A should not have D'
    end

    def test_constant_caching_via_const_set
      # Create package A with a constant
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'cached'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # First access triggers const_missing and caching
      assert_equal 'cached', root_box.eval('A::ClassA.value')

      # Second access should use cached constant (no const_missing)
      assert_equal 'cached', root_box.eval('A::ClassA.value')
    end

    # --- Privacy enforcement tests ---

    def test_privacy_blocks_private_constant
      # Package A has enforce_privacy: true, only Invoice is public
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)

      # Create public dir with public constant
      pub_dir = File.join(a_dir, 'app', 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\n  def self.value\n    'public'\n  end\nend\n")

      # Create private constant in lib
      File.write(File.join(a_dir, 'lib', 'secret.rb'), "class Secret\n  def self.value\n    'private'\n  end\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Public constant is accessible
      assert_equal 'public', root_box.eval('A::Invoice.value')

      # Private constant is blocked
      assert_raises(NameError) { root_box.eval('A::Secret') }
    end

    def test_privacy_allows_all_when_not_enforced
      # Package A without enforce_privacy
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'secret.rb'),
        "class Secret\n  def self.value\n    'accessible'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Without privacy, all constants are accessible
      assert_equal 'accessible', root_box.eval('A::Secret.value')
    end

    def test_privacy_pack_public_sigil
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)

      # Create a file with pack_public sigil in lib (not in public path)
      File.write(
        File.join(a_dir, 'lib', 'publicized.rb'),
        "# pack_public: true\nclass Publicized\n  def self.value\n    'sigil'\n  end\nend\n",
      )

      # Create a private file without sigil
      File.write(
        File.join(a_dir, 'lib', 'private_thing.rb'),
        "class PrivateThing\n  def self.value\n    'hidden'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Sigil file is accessible
      assert_equal 'sigil', root_box.eval('A::Publicized.value')

      # Non-sigil file is blocked
      assert_raises(NameError) { root_box.eval('A::PrivateThing') }
    end

    def test_privacy_explicit_private_constants
      a_dir = create_package_dir('a')
      create_package(a_dir,
        enforce_privacy: true,
        private_constants: ['::A::Invoice'])

      # Even though Invoice is in public path, it's explicitly private
      pub_dir = File.join(a_dir, 'app', 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\nend\n")
      File.write(File.join(pub_dir, 'report.rb'), "class Report\n  def self.value\n    'report'\n  end\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Report is public and accessible
      assert_equal 'report', root_box.eval('A::Report.value')

      # Invoice is explicitly private
      assert_raises(NameError) { root_box.eval('A::Invoice') }
    end

    # --- Visibility enforcement tests ---

    def test_visibility_blocks_non_visible_package
      # Package A is visible only to package C
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_visibility: true, visible_to: ['packages/c'])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      # Root depends on A but is NOT in visible_to
      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      # Root cannot see A (not in visible_to list)
      refute root_box.eval('defined?(A)'), 'Root should not have A (visibility blocked)'
    end

    def test_visibility_allows_visible_package
      # Package A is visible to root (.)
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_visibility: true, visible_to: ['.'])
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'visible'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      assert_equal 'visible', root_box.eval('A::ClassA.value')
    end

    def test_visibility_not_enforced_allows_all
      a_dir = create_package_dir('a')
      create_package(a_dir) # No enforce_visibility
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'open'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      assert_equal 'open', root_box.eval('A::ClassA.value')
    end

    # --- Folder privacy enforcement tests ---

    def test_folder_privacy_allows_sibling
      # Create nested packs structure
      packs_dir = File.join(@tmpdir, 'packs', 'parent', 'packs')
      FileUtils.mkdir_p(packs_dir)

      # Create parent pack
      parent_dir = File.join(@tmpdir, 'packs', 'parent')
      create_package(parent_dir, dependencies: ['packs/parent/packs/target', 'packs/parent/packs/sibling'])

      # Create target (folder_privacy enforced)
      target_dir = File.join(packs_dir, 'target')
      FileUtils.mkdir_p(File.join(target_dir, 'lib'))
      create_package(target_dir, enforce_folder_privacy: true)
      File.write(
        File.join(target_dir, 'lib', 'target_class.rb'),
        "class TargetClass\n  def self.value\n    'from_target'\n  end\nend\n",
      )

      # Create sibling (same parent)
      sibling_dir = File.join(packs_dir, 'sibling')
      FileUtils.mkdir_p(File.join(sibling_dir, 'lib'))
      create_package(sibling_dir, dependencies: ['packs/parent/packs/target'])
      File.write(File.join(sibling_dir, 'lib', 'sibling_class.rb'), "class SiblingClass\nend\n")

      create_package(@tmpdir, dependencies: ['packs/parent'])

      result = boot_system

      # Sibling should be able to access target
      sibling_box = result[:box_manager].boxes['packs/parent/packs/sibling']
      assert sibling_box.eval('defined?(Target)'), 'Sibling should see Target'
    end

    def test_folder_privacy_blocks_unrelated
      # Create two unrelated packs in different parent directories
      a_parent = File.join(@tmpdir, 'packs', 'alpha')
      a_dir = File.join(a_parent, 'packs', 'a')
      FileUtils.mkdir_p(File.join(a_dir, 'lib'))
      create_package(a_dir, enforce_folder_privacy: true)
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      # Alpha parent pack
      FileUtils.mkdir_p(File.join(a_parent, 'lib'))
      create_package(a_parent, dependencies: ['packs/alpha/packs/a'])

      b_parent = File.join(@tmpdir, 'packs', 'beta')
      b_dir = File.join(b_parent, 'packs', 'b')
      FileUtils.mkdir_p(File.join(b_dir, 'lib'))
      create_package(b_dir, dependencies: ['packs/alpha/packs/a'])
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      FileUtils.mkdir_p(File.join(b_parent, 'lib'))
      create_package(b_parent, dependencies: ['packs/beta/packs/b'])

      create_package(@tmpdir, dependencies: %w[packs/alpha packs/beta])

      result = boot_system

      # B (in beta) cannot access A (in alpha) — different parent
      b_box = result[:box_manager].boxes['packs/beta/packs/b']
      refute b_box.eval('defined?(A)'), 'Unrelated B should not see A (folder privacy blocked)'
    end

    # --- Layer enforcement tests ---

    def test_layer_allows_same_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_layers: true, layer: 'core')
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'core'\n  end\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir, enforce_layers: true, layer: 'core', dependencies: ['packages/a'])
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: %w[packages/a packages/b])

      result = boot_system

      b_box = result[:box_manager].boxes['packages/b']
      assert_equal 'core', b_box.eval('A::ClassA.value')
    end

    def test_layer_allows_lower_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      util_dir = create_package_dir('util')
      create_package(util_dir, layer: 'utility')
      File.write(
        File.join(util_dir, 'lib', 'util_class.rb'),
        "class UtilClass\n  def self.value\n    'util'\n  end\nend\n",
      )

      feature_dir = create_package_dir('feature')
      create_package(feature_dir, enforce_layers: true, layer: 'feature', dependencies: ['packages/util'])
      File.write(File.join(feature_dir, 'lib', 'feature_class.rb'), "class FeatureClass\nend\n")

      create_package(@tmpdir, dependencies: %w[packages/util packages/feature])

      result = boot_system

      feature_box = result[:box_manager].boxes['packages/feature']
      assert_equal 'util', feature_box.eval('Util::UtilClass.value')
    end

    def test_layer_blocks_higher_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      feature_dir = create_package_dir('feature')
      create_package(feature_dir, layer: 'feature')
      File.write(File.join(feature_dir, 'lib', 'feature_class.rb'), "class FeatureClass\nend\n")

      util_dir = create_package_dir('util')
      create_package(util_dir, enforce_layers: true, layer: 'utility', dependencies: ['packages/feature'])
      File.write(File.join(util_dir, 'lib', 'util_class.rb'), "class UtilClass\nend\n")

      create_package(@tmpdir, dependencies: %w[packages/feature packages/util])

      assert_raises(Boxwerk::LayerViolationError) { boot_system }
    end

    # --- Gem isolation tests ---

    def test_per_package_gem_loading
      a_dir = create_package_dir('a')
      create_package(a_dir)

      # Create a Gemfile.lock referencing json (always installed)
      json_spec = Gem::Specification.find_by_name('json')
      File.write(File.join(a_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'json'\n")
      File.write(File.join(a_dir, 'Gemfile.lock'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            json (#{json_spec.version})

        PLATFORMS
          arm64-darwin-25

        DEPENDENCIES
          json

        BUNDLED WITH
           2.7.5
      LOCK

      File.write(
        File.join(a_dir, 'lib', 'json_user.rb'),
        "class JsonUser\n  def self.parse\n    require 'json'\n    JSON.parse('[1,2,3]')\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      parsed = root_box.eval('A::JsonUser.parse')
      assert_equal [1, 2, 3], parsed
    end

    def test_gem_isolation_between_packages
      a_dir = create_package_dir('a')
      create_package(a_dir)

      b_dir = create_package_dir('b')
      create_package(b_dir)

      # Create fake gem dirs with different versions
      a_gem_dir = File.join(@tmpdir, 'gems_v1', 'lib')
      FileUtils.mkdir_p(a_gem_dir)
      File.write(File.join(a_gem_dir, 'my_lib.rb'), "module MyLib\n  VERSION = '1.0'\nend\n")

      b_gem_dir = File.join(@tmpdir, 'gems_v2', 'lib')
      FileUtils.mkdir_p(b_gem_dir)
      File.write(File.join(b_gem_dir, 'my_lib.rb'), "module MyLib\n  VERSION = '2.0'\nend\n")

      File.write(
        File.join(a_dir, 'lib', 'a_service.rb'),
        "class AService\n  def self.version\n    $LOAD_PATH.unshift('#{a_gem_dir}')\n    require 'my_lib'\n    MyLib::VERSION\n  end\nend\n",
      )

      File.write(
        File.join(b_dir, 'lib', 'b_service.rb'),
        "class BService\n  def self.version\n    $LOAD_PATH.unshift('#{b_gem_dir}')\n    require 'my_lib'\n    MyLib::VERSION\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: %w[packages/a packages/b])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      assert_equal '1.0', root_box.eval('A::AService.version')
      assert_equal '2.0', root_box.eval('B::BService.version')
    end

    # --- Multiple constants ---

    def test_multiple_constants_from_same_package
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(File.join(a_dir, 'lib', 'foo.rb'), "class Foo\n  def self.name = 'foo'\nend\n")
      File.write(File.join(a_dir, 'lib', 'bar.rb'), "class Bar\n  def self.name = 'bar'\nend\n")
      File.write(File.join(a_dir, 'lib', 'baz.rb'), "class Baz\n  def self.name = 'baz'\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      assert_equal 'foo', root_box.eval('A::Foo.name')
      assert_equal 'bar', root_box.eval('A::Bar.name')
      assert_equal 'baz', root_box.eval('A::Baz.name')
    end

    def test_descriptive_error_for_privacy_violation
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)
      File.write(File.join(a_dir, 'lib', 'secret.rb'), "class Secret\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']

      error = assert_raises(NameError) { root_box.eval('A::Secret') }
      assert_match(/Privacy violation/, error.message)
      assert_match(/packages\/a/, error.message)
    end

    def create_package_dir(name)
      dir = File.join(@tmpdir, 'packages', name)
      FileUtils.mkdir_p(File.join(dir, 'lib'))
      dir
    end

    def create_package(path, dependencies: nil, enforce_privacy: nil, private_constants: nil,
                       enforce_visibility: nil, visible_to: nil,
                       enforce_folder_privacy: nil,
                       enforce_layers: nil, layer: nil)
      content = { 'enforce_dependencies' => true }
      content['dependencies'] = dependencies if dependencies
      content['enforce_privacy'] = enforce_privacy unless enforce_privacy.nil?
      content['private_constants'] = private_constants if private_constants
      content['enforce_visibility'] = enforce_visibility unless enforce_visibility.nil?
      content['visible_to'] = visible_to if visible_to
      content['enforce_folder_privacy'] = enforce_folder_privacy unless enforce_folder_privacy.nil?
      content['enforce_layers'] = enforce_layers unless enforce_layers.nil?
      content['layer'] = layer if layer

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end

    def boot_system
      resolver = PackageResolver.new(@tmpdir)
      box_manager = BoxManager.new(@tmpdir)
      box_manager.boot_all(resolver)

      { resolver: resolver, box_manager: box_manager }
    end
  end
end
