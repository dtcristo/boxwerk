# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for folder privacy enforcement: sibling access allowed,
  # parent access allowed, unrelated packages blocked.
  class FolderPrivacyIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_folder_privacy_allows_sibling
      packs_dir = File.join(@tmpdir, 'packs', 'parent', 'packs')
      FileUtils.mkdir_p(packs_dir)

      parent_dir = File.join(@tmpdir, 'packs', 'parent')
      create_package(parent_dir, dependencies: ['packs/parent/packs/target', 'packs/parent/packs/sibling'])

      target_dir = File.join(packs_dir, 'target')
      FileUtils.mkdir_p(File.join(target_dir, 'lib'))
      create_package(target_dir, enforce_folder_privacy: true)
      File.write(
        File.join(target_dir, 'lib', 'target_class.rb'),
        "class TargetClass\n  def self.value\n    'from_target'\n  end\nend\n",
      )

      sibling_dir = File.join(packs_dir, 'sibling')
      FileUtils.mkdir_p(File.join(sibling_dir, 'lib'))
      create_package(sibling_dir, dependencies: ['packs/parent/packs/target'])
      File.write(File.join(sibling_dir, 'lib', 'sibling_class.rb'), "class SiblingClass\nend\n")

      create_package(@tmpdir, dependencies: ['packs/parent'])

      result = boot_system

      sibling_box = result[:box_manager].boxes['packs/parent/packs/sibling']
      assert sibling_box.eval('defined?(Target)'), 'Sibling should see Target'
    end

    def test_folder_privacy_blocks_unrelated
      a_parent = File.join(@tmpdir, 'packs', 'alpha')
      a_dir = File.join(a_parent, 'packs', 'a')
      FileUtils.mkdir_p(File.join(a_dir, 'lib'))
      create_package(a_dir, enforce_folder_privacy: true)
      File.write(File.join(a_dir, 'lib', 'class_a.rb'), "class ClassA\nend\n")

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

      b_box = result[:box_manager].boxes['packs/beta/packs/b']
      refute b_box.eval('defined?(A)'), 'Unrelated B should not see A (folder privacy blocked)'
    end
  end
end
