# frozen_string_literal: true

require 'minitest/autorun'

class CalculatorTest < Minitest::Test
  def test_add
    assert_equal 5, Calculator.add(2, 3)
  end

  def test_subtract
    assert_equal 1, Calculator.subtract(3, 2)
  end

  def test_multiply
    assert_equal 6, Calculator.multiply(2, 3)
  end

  def test_divide
    assert_in_delta 2.5, Calculator.divide(5, 2)
  end

  def test_divide_by_zero
    assert_raises(ArgumentError) { Calculator.divide(1, 0) }
  end
end
