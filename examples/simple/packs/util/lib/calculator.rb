# frozen_string_literal: true

require 'faker'

class Calculator
  def self.add(a, b)
    a + b
  end

  def self.subtract(a, b)
    a - b
  end

  def self.multiply(a, b)
    a * b
  end

  def self.divide(a, b)
    raise ArgumentError, 'Cannot divide by zero' if b.zero?
    a.to_f / b
  end

  def self.faker_version
    Faker::VERSION
  end
end
