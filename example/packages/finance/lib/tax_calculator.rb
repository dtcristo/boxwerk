# frozen_string_literal: true

# TaxCalculator provides tax calculation utilities
# Uses the imported MathLib package for calculations
class TaxCalculator
  STANDARD_RATE = 0.10 # 10%
  LUXURY_RATE = 0.20 # 20%

  def self.calculate_tax(amount, rate = STANDARD_RATE)
    # Use MathCalculator from selective import
    MathCalculator.multiply(amount, rate)
  end

  def self.calculate_total(amount, rate = STANDARD_RATE)
    tax = calculate_tax(amount, rate)
    # Use MathCalculator.add from selective import
    MathCalculator.add(amount, tax)
  end

  def self.reverse_calculate(total_with_tax, rate = STANDARD_RATE)
    # Calculate original amount from total including tax
    # Formula: original = total / (1 + rate)
    divisor = MathCalculator.add(1, rate)
    MathCalculator.divide(total_with_tax, divisor)
  end
end
