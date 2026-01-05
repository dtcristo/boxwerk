# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class RegistryTest < Minitest::Test
    def setup
      @registry = Registry.new
    end

    def test_register_and_get
      package = Object.new
      @registry.register('math', package)

      assert @registry.registered?('math')
      assert_equal package, @registry.get('math')
      assert_nil @registry.get('nonexistent')
    end

    def test_clear
      @registry.register('math', Object.new)
      @registry.clear!

      refute @registry.registered?('math')
    end
  end
end
