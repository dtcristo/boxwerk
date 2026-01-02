# frozen_string_literal: true

# Invoice represents a financial invoice with line items and tax calculation
# Uses the Money gem for precise currency handling
class Invoice
  attr_reader :items, :tax_rate

  def initialize(tax_rate: TaxCalculator::STANDARD_RATE)
    @items = []
    @tax_rate = tax_rate
  end

  def add_item(description, amount_cents)
    @items << {
      description: description,
      amount: Money.new(amount_cents, 'USD'),
    }
    self
  end

  def subtotal
    @items.reduce(Money.new(0, 'USD')) { |sum, item| sum + item[:amount] }
  end

  def tax
    (subtotal * tax_rate).round
  end

  def total
    subtotal + tax
  end

  def to_h
    {
      items:
        @items.map do |item|
          { description: item[:description], amount: item[:amount].cents }
        end,
      subtotal: subtotal.cents,
      tax_rate: tax_rate,
      tax: tax.cents,
      total: total.cents,
    }
  end

  def self.quick_invoice(amount_cents, tax_rate: TaxCalculator::STANDARD_RATE)
    invoice = new(tax_rate: tax_rate)
    invoice.add_item('Service', amount_cents)
    invoice
  end
end
