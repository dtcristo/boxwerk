# frozen_string_literal: true

require 'minitest/autorun'

class GreetingTest < Minitest::Test
  def test_hello_returns_string
    assert_kind_of String, Greeting.hello
  end

  def test_hello_not_empty
    refute_empty Greeting.hello
  end
end
