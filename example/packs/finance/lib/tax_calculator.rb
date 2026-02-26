# frozen_string_literal: true

class TaxCalculator
  def self.calculate(amount_cents, rate)
    (Calculator.multiply(amount_cents, rate)).round
  end
end
