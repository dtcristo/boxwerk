# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class ConstantResolverTest < Minitest::Test
    def test_build_resolver_returns_proc
      resolver = ConstantResolver.build_resolver([])
      assert_kind_of Proc, resolver
    end
  end
end
