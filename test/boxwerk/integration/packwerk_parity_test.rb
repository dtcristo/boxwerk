# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests that verify Boxwerk runtime enforcement matches what Packwerk
  # would catch via static analysis. For each scenario, we verify:
  # 1. The package dependency graph is set up correctly
  # 2. Boxwerk enforces the same constraint at runtime
  class PackwerkParityTest < Minitest::Test
    include IntegrationTestHelper

    def test_undeclared_dependency_blocked_at_runtime
      a_dir = create_package_dir('a')
      create_package(a_dir) # no dependencies
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      b_dir = create_package_dir('b')
      create_package(b_dir)
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      resolver = result[:resolver]
      a_pkg = resolver.packages['packs/a']
      refute_includes a_pkg.dependencies, 'packs/b',
                      'Packwerk: A should not declare B as dependency'

      a_box = result[:box_manager].boxes['packs/a']
      refute a_box.eval('defined?(ClassB)'),
             'Boxwerk: A should not have ClassB (undeclared dependency)'
    end

    def test_declared_dependency_allowed_at_runtime
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

      resolver = result[:resolver]
      a_pkg = resolver.packages['packs/a']
      assert_includes a_pkg.dependencies, 'packs/b',
                      'Packwerk: A should declare B as dependency'

      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'allowed', a_box.eval('ClassB.value'),
                   'Boxwerk: A should access ClassB'
    end

    def test_privacy_violation_blocked_at_runtime
      b_dir = create_package_dir('b')
      create_package(b_dir, enforce_privacy: true)

      pub_dir = File.join(b_dir, 'public')
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

      resolver = result[:resolver]
      b_pkg = resolver.packages['packs/b']
      assert b_pkg.config['enforce_privacy'],
             'Packwerk: B should enforce privacy'

      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'public', a_box.eval('Api.call'),
                   'Boxwerk: public constant should be accessible'

      error = assert_raises(NameError) { a_box.eval('Secret') }
      assert_match(/Privacy violation/, error.message,
                   'Boxwerk: private constant should raise privacy error')
    end

    def test_transitive_dependency_matches_packwerk_violation
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
        "class Surface\n  def self.value\n    Deep.value\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system

      resolver = result[:resolver]
      root_pkg = resolver.root
      refute_includes root_pkg.dependencies, 'packs/b'

      root_box = result[:box_manager].boxes['.']
      assert root_box.eval('defined?(Surface)'), 'Root should see Surface'
      assert_raises(NameError) { root_box.eval('Deep') }

      # But A CAN access Deep (direct dependency)
      a_box = result[:box_manager].boxes['packs/a']
      assert_equal 'deep', a_box.eval('Deep.value')
    end
  end
end
