# frozen_string_literal: true

# Geometry provides geometric calculations
class Geometry
  PI = 3.14159265359

  def self.circle_area(radius)
    PI * radius * radius
  end

  def self.circle_circumference(radius)
    2 * PI * radius
  end

  def self.rectangle_area(width, height)
    width * height
  end

  def self.rectangle_perimeter(width, height)
    2 * (width + height)
  end

  def self.triangle_area(base, height)
    (base * height) / 2.0
  end
end
