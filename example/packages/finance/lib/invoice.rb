# frozen_string_literal: true

class Invoice
  attr_reader :items, :tax_rate

  def initialize(tax_rate: 0.10)
    @items = []
    @tax_rate = tax_rate
  end

  def add_item(description, amount_cents)
    @items << { description: description, amount: Money.new(amount_cents, 'USD') }
    self
  end

  def subtotal
    @items.reduce(Money.new(0, 'USD')) { |sum, item| sum + item[:amount] }
  end

  def tax
    TaxCalculator.calculate(subtotal.cents, tax_rate)
  end

  def total
    subtotal + tax
  end
end
