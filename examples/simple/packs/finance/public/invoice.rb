# frozen_string_literal: true

class Invoice
  attr_reader :items, :tax_rate

  def initialize(tax_rate: 0.10)
    @items = []
    @tax_rate = tax_rate
  end

  def add_item(description, amount_cents)
    @items << { description: description, amount: amount_cents }
    self
  end

  def subtotal
    @items.sum { |item| item[:amount] }
  end

  def tax
    TaxCalculator.calculate(subtotal, tax_rate)
  end

  def total
    subtotal + tax
  end

  # Exposes the faker version from the util pack (via Calculator).
  def self.faker_version
    Calculator.faker_version
  end
end
