# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests that verify Boxwerk runtime enforcement matches what Packwerk
  # would catch via static analysis. For each scenario, we verify:
  # 1. The package dependency graph is set up correctly via Packwerk API
  # 2. Boxwerk enforces the same constraint at runtime
  class PackwerkParityTest < Minitest::Test
    include IntegrationTestHelper

    def test_undeclared_dependency_blocked_at_runtime
      # Packwerk: package A does NOT list B as a dependency
      # Packwerk check would flag: "packs/a cannot depend on packs/b"
      # Boxwerk: A cannot access B:: namespace at runtime
      a_dir = create_package_dir('a')
      create_package(a_dir) # no dependencies
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      # Verify via Packwerk API: A does not declare B as dependency
      resolver = result[:resolver]
      a_pkg = resolver.packages['packs/a']
      refute_includes a_pkg.dependencies, 'packs/b',
                      'Packwerk: A should not declare B as dependency'

      # Verify Boxwerk runtime: A cannot access B namespace
      a_box = result[:box_manager].boxes['packs/a']
      refute a_box.eval('defined?(B)'),
             'Boxwerk: A should not have B namespace (undeclared dependency)'
    end

    def test_declared_dependency_allowed_at_runtime
      # Packwerk: package A lists B as a dependency — no violation
      # Boxwerk: A can access B:: namespace at runtime
      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/b'])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'class_b.rb'),
        "class ClassB\n  def self.value\n    'allowed'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      # Verify via Packwerk API: A declares B
      resolver = result[:resolver]
      a_pkg = resolver.packages['packs/a']
      assert_includes a_pkg.dependencies, 'packs/b',
                      'Packwerk: A should declare B as dependency'

      # Verify Boxwerk runtime: A can access B
      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'allowed', a_box.eval('B::ClassB.value'),
                   'Boxwerk: A should access B::ClassB'
    end

    def test_privacy_violation_blocked_at_runtime
      # Packwerk-extensions: B enforces privacy, Secret is not in public_path
      # packwerk check would flag: "Privacy violation for ::B::Secret"
      # Boxwerk: accessing B::Secret raises NameError with privacy message
      b_dir = create_package_dir('b')
      create_package(b_dir, enforce_privacy: true)

      pub_dir = File.join(b_dir, 'app', 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(
        File.join(pub_dir, 'api.rb'),
        "class Api\n  def self.call\n    'public'\n  end\nend\n",
      )
      File.write(File.join(b_dir, 'lib', 'secret.rb'), "class Secret\nend\n")

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/b'])

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      # Verify via Packwerk config: B enforces privacy
      resolver = result[:resolver]
      b_pkg = resolver.packages['packs/b']
      assert b_pkg.config['enforce_privacy'],
             'Packwerk: B should enforce privacy'

      # Verify Boxwerk runtime
      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'public', a_box.eval('B::Api.call'),
                   'Boxwerk: public constant should be accessible'

      error = assert_raises(NameError) { a_box.eval('B::Secret') }
      assert_match(/Privacy violation/, error.message,
                   'Boxwerk: private constant should raise privacy error')
    end

    def test_visibility_violation_blocked_at_runtime
      # Packwerk-extensions: C is visible only to B, not A
      # packwerk check would flag: "packs/a cannot depend on packs/c (visibility)"
      # Boxwerk: A cannot see C namespace at runtime
      c_dir = create_package_dir('c')
      create_package(c_dir, enforce_visibility: true, visible_to: ['packs/b'])
      File.write(File.join(c_dir, 'lib', 'class_c.rb'), "class ClassC\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir, dependencies: ['packs/c'])

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: %w[packs/b packs/c])

      create_package(@tmpdir, dependencies: %w[packs/a packs/b packs/c])

      result = boot_system

      # Verify config: C is visible to B only
      resolver = result[:resolver]
      c_pkg = resolver.packages['packs/c']
      assert c_pkg.config['enforce_visibility']
      assert_equal ['packs/b'], c_pkg.config['visible_to']

      # Boxwerk runtime: B can see C, A cannot
      b_box = result[:box_manager].boxes['packs/b']
      assert b_box.eval('defined?(C)'), 'Boxwerk: B should see C (in visible_to)'

      a_box = result[:box_manager].boxes['packs/a']
      refute a_box.eval('defined?(C)'), 'Boxwerk: A should not see C (not in visible_to)'
    end

    def test_layer_violation_blocked_at_boot
      # Packwerk-extensions: utility layer cannot depend on feature layer
      # packwerk check would flag: "Layer violation"
      # Boxwerk: raises LayerViolationError at boot time
      File.write(
        File.join(@tmpdir, 'packwerk.yml'),
        YAML.dump('layers' => %w[feature core utility]),
      )

      feature_dir = create_package_dir('feature')
      create_package(feature_dir, layer: 'feature')
      File.write(File.join(feature_dir, 'lib', 'feat.rb'), "class Feat\nend\n")

      util_dir = create_package_dir('util')
      create_package(util_dir, enforce_layers: true, layer: 'utility',
                     dependencies: ['packs/feature'])
      File.write(File.join(util_dir, 'lib', 'util_class.rb'), "class UtilClass\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/feature packs/util])

      # Verify layer config
      layers = LayerChecker.layers_for(@tmpdir)
      assert_equal %w[feature core utility], layers

      # Boxwerk: raises at boot
      error = assert_raises(LayerViolationError) { boot_system }
      assert_match(/utility.*cannot depend on.*feature/i, error.message)
    end

    def test_transitive_dependency_matches_packwerk_violation
      # Packwerk: root depends on A, A depends on B. Root does NOT declare B.
      # packwerk check would flag root accessing B constants
      # Boxwerk: root cannot access B:: namespace
      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(
        File.join(b_dir, 'lib', 'deep.rb'),
        "class Deep\n  def self.value\n    'deep'\n  end\nend\n",
      )

      a_dir = create_package_dir('a')
      create_package(a_dir, dependencies: ['packs/b'])
      File.write(
        File.join(a_dir, 'lib', 'surface.rb'),
        "class Surface\n  def self.value\n    B::Deep.value\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system

      # Packwerk: root does not declare B
      resolver = result[:resolver]
      root_pkg = resolver.root
      refute_includes root_pkg.dependencies, 'packs/b'

      # Boxwerk: root can access A but not B
      root_box = result[:box_manager].boxes['.']
      assert root_box.eval('defined?(A)'), 'Root should see A'
      assert_raises(NameError) { root_box.eval('B') }

      # But A CAN access B (direct dependency)
      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'deep', a_box.eval('B::Deep.value')
    end
  end
end
