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

  # Isolation: orders depends only on packs/menu.
  # Constants from packages that are not direct dependencies are blocked.
  #
  # Note: qualified access via a shared namespace (e.g. Menu::Recipe) is not
  # blocked at the box level once the parent module is resolved — this is a
  # known limitation of the Ruby::Box approach.
  def test_cannot_access_loyalty
    assert_raises(NameError) { Loyalty }
  end

  def test_cannot_access_kitchen
    assert_raises(NameError) { Kitchen }
  end
end
