# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class VisibilityCheckerTest < Minitest::Test
    def test_enforces_visibility_when_true
      pkg = Package.new(name: 'packages/a', config: { 'enforce_visibility' => true })
      assert VisibilityChecker.enforces_visibility?(pkg)
    end

    def test_does_not_enforce_visibility_when_false
      pkg = Package.new(name: 'packages/a', config: { 'enforce_visibility' => false })
      refute VisibilityChecker.enforces_visibility?(pkg)
    end

    def test_does_not_enforce_visibility_when_absent
      pkg = Package.new(name: 'packages/a', config: {})
      refute VisibilityChecker.enforces_visibility?(pkg)
    end

    def test_visible_when_accessor_in_visible_to
      target = Package.new(
        name: 'packages/a',
        config: { 'enforce_visibility' => true, 'visible_to' => ['packages/b'] },
      )
      accessor = Package.new(name: 'packages/b', config: {})
      assert VisibilityChecker.visible?(target, accessor)
    end

    def test_not_visible_when_accessor_not_in_visible_to
      target = Package.new(
        name: 'packages/a',
        config: { 'enforce_visibility' => true, 'visible_to' => ['packages/b'] },
      )
      accessor = Package.new(name: 'packages/c', config: {})
      refute VisibilityChecker.visible?(target, accessor)
    end

    def test_visible_when_not_enforced
      target = Package.new(name: 'packages/a', config: {})
      accessor = Package.new(name: 'packages/c', config: {})
      assert VisibilityChecker.visible?(target, accessor)
    end
  end
end
