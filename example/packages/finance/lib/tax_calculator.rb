# frozen_string_literal: true

class TaxCalculator
  def self.calculate(amount_cents, rate)
    tax_cents = UtilCalculator.multiply(amount_cents, rate).round
    Money.new(tax_cents, 'USD')
  end
end
