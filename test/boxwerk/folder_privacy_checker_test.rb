# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class FolderPrivacyCheckerTest < Minitest::Test
    def test_enforces_when_true
      pkg = Package.new(name: 'packs/a', config: { 'enforce_folder_privacy' => true })
      assert FolderPrivacyChecker.enforces_folder_privacy?(pkg)
    end

    def test_does_not_enforce_when_false
      pkg = Package.new(name: 'packs/a', config: {})
      refute FolderPrivacyChecker.enforces_folder_privacy?(pkg)
    end

    def test_sibling_can_access
      target = Package.new(
        name: 'packs/b/packs/e',
        config: { 'enforce_folder_privacy' => true },
      )
      sibling = Package.new(name: 'packs/b/packs/d', config: {})
      assert FolderPrivacyChecker.accessible?(target, sibling)
    end

    def test_parent_can_access
      target = Package.new(
        name: 'packs/b/packs/e',
        config: { 'enforce_folder_privacy' => true },
      )
      parent = Package.new(name: 'packs/b', config: {})
      assert FolderPrivacyChecker.accessible?(target, parent)
    end

    def test_root_can_access
      target = Package.new(
        name: 'packs/b/packs/e',
        config: { 'enforce_folder_privacy' => true },
      )
      root = Package.new(name: '.', config: {})
      assert FolderPrivacyChecker.accessible?(target, root)
    end

    def test_unrelated_package_blocked
      target = Package.new(
        name: 'packs/alpha/packs/e',
        config: { 'enforce_folder_privacy' => true },
      )
      unrelated = Package.new(name: 'packs/beta/packs/f', config: {})
      refute FolderPrivacyChecker.accessible?(target, unrelated)
    end

    def test_child_package_blocked
      target = Package.new(
        name: 'packs/b/packs/e',
        config: { 'enforce_folder_privacy' => true },
      )
      child = Package.new(name: 'packs/b/packs/e/packs/f', config: {})
      refute FolderPrivacyChecker.accessible?(target, child)
    end

    def test_not_enforced_allows_all
      target = Package.new(name: 'packs/b/packs/e', config: {})
      unrelated = Package.new(name: 'packs/a', config: {})
      assert FolderPrivacyChecker.accessible?(target, unrelated)
    end
  end
end
