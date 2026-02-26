# frozen_string_literal: true

require 'json'

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

  def self.to_json_report(operations)
    JSON.generate(operations)
  end
end
