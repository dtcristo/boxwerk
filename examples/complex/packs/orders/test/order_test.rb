# frozen_string_literal: true

require 'minitest/autorun'

class OrderTest < Minitest::Test
  def test_empty_order
    order = Orders::Order.new
    assert_equal 0, order.total_cents
  end

  def test_add_items
    item = Menu::Item.new(name: 'Latte', price_cents: 550)
    order = Orders::Order.new
    order.add(item, quantity: 2)
    assert_equal 1100, order.total_cents
  end

  def test_total_formatting
    item = Menu::Item.new(name: 'Espresso', price_cents: 350)
    order = Orders::Order.new
    order.add(item)
    assert_equal '$3.50', order.total
  end

  def test_line_item_accessible_internally
    item = Menu::Item.new(name: 'Tea', price_cents: 300)
    line = Orders::LineItem.new(menu_item: item, quantity: 3)
    assert_equal 900, line.total_cents
  end
end
