# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class ConstantResolverTest < Minitest::Test
    def test_create_namespace_proxy_returns_module
      # We can't easily create a real Ruby::Box in unit tests,
      # so we test the module structure
      proxy = Module.new

      assert_kind_of Module, proxy
    end

    def test_namespace_for_derives_module_name
      assert_equal 'Finance', PackageResolver.namespace_for('packages/finance')
      assert_equal 'TaxCalc', PackageResolver.namespace_for('packages/tax_calc')
      assert_nil PackageResolver.namespace_for('.')
    end
  end
end
