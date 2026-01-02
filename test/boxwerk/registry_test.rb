# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class RegistryTest < Minitest::Test
    def setup
      @registry = Registry.new
    end

    def test_initialization
      assert_instance_of Registry, @registry
      refute @registry.registered?(:test)
    end

    def test_register_package
      package = Object.new

      @registry.register(:math, package)

      assert @registry.registered?(:math)
      assert_equal package, @registry.get(:math)
    end

    def test_get_nonexistent_package
      result = @registry.get(:nonexistent)

      assert_nil result
    end

    def test_registered_returns_false_for_nonexistent
      refute @registry.registered?(:nonexistent)
    end

    def test_register_multiple_packages
      package1 = Object.new
      package2 = Object.new
      package3 = Object.new

      @registry.register(:math, package1)
      @registry.register(:utils, package2)
      @registry.register(:billing, package3)

      assert @registry.registered?(:math)
      assert @registry.registered?(:utils)
      assert @registry.registered?(:billing)
      assert_equal package1, @registry.get(:math)
      assert_equal package2, @registry.get(:utils)
      assert_equal package3, @registry.get(:billing)
    end

    def test_overwrite_registered_package
      package1 = Object.new
      package2 = Object.new

      @registry.register(:math, package1)
      assert_equal package1, @registry.get(:math)

      @registry.register(:math, package2)
      assert_equal package2, @registry.get(:math)
    end

    def test_clear
      @registry.register(:math, Object.new)
      @registry.register(:utils, Object.new)

      assert @registry.registered?(:math)
      assert @registry.registered?(:utils)

      @registry.clear!

      refute @registry.registered?(:math)
      refute @registry.registered?(:utils)
    end

    def test_clear_on_empty_registry
      @registry.clear!

      refute @registry.registered?(:anything)
    end

    def test_register_with_string_name
      package = Object.new
      @registry.register('math', package)

      assert @registry.registered?('math')
      assert_equal package, @registry.get('math')
    end

    def test_symbol_and_string_keys_are_different
      package1 = Object.new
      package2 = Object.new

      @registry.register(:math, package1)
      @registry.register('math', package2)

      assert_equal package1, @registry.get(:math)
      assert_equal package2, @registry.get('math')
    end
  end
end
