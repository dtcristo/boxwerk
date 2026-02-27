# frozen_string_literal: true

require 'minitest/autorun'

class InvoiceTest < Minitest::Test
  def test_empty_invoice
    invoice = Invoice.new
    assert_equal 0, invoice.subtotal
    assert_equal 0, invoice.tax
    assert_equal 0, invoice.total
  end

  def test_add_item
    invoice = Invoice.new(tax_rate: 0.10)
    invoice.add_item('Service', 10_000)
    assert_equal 10_000, invoice.subtotal
  end

  def test_tax_calculation
    invoice = Invoice.new(tax_rate: 0.20)
    invoice.add_item('Service', 10_000)
    assert_equal 2_000, invoice.tax
  end

  def test_total
    invoice = Invoice.new(tax_rate: 0.10)
    invoice.add_item('Service', 10_000)
    assert_equal 11_000, invoice.total
  end

  def test_multiple_items
    invoice = Invoice.new(tax_rate: 0.15)
    invoice.add_item('A', 5_000)
    invoice.add_item('B', 3_000)
    assert_equal 8_000, invoice.subtotal
    assert_equal 1_200, invoice.tax
    assert_equal 9_200, invoice.total
  end

  def test_items_are_line_items
    invoice = Invoice.new
    invoice.add_item('Widget', 5_000)
    item = invoice.items.first
    assert_equal 'Widget', item.description
    assert_equal 5_000, item.amount_cents
    assert_equal 'Widget: 5000', item.to_s
    assert_equal 'LineItem', item.class.name
  end
end
