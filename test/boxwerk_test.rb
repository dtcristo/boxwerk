# frozen_string_literal: true

require 'test_helper'

class BoxwerkTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Boxwerk::VERSION
  end

  def test_version_format
    assert_match(/^\d+\.\d+\.\d+$/, ::Boxwerk::VERSION)
  end
end
