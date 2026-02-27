# frozen_string_literal: true

require 'minitest/autorun'

class GeometryTest < Minitest::Test
  def test_circle_area
    area = Geometry.circle_area(10)
    assert_in_delta 314.159, area, 0.001
  end

  def test_pi_constant
    assert_in_delta 3.14159, Geometry::PI, 0.00001
  end
end
