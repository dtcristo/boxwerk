# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for visibility enforcement: visible_to allows listed packages,
  # blocks unlisted packages, and is not enforced when absent.
  class VisibilityIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_visibility_blocks_non_visible_package
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_visibility: true, visible_to: ['packages/c'])
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      refute root_box.eval('defined?(A)'), 'Root should not have A (visibility blocked)'
    end

    def test_visibility_allows_visible_package
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
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'open'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'open', root_box.eval('A::ClassA.value')
    end
  end
end
