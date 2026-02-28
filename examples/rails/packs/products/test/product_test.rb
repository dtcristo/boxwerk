# frozen_string_literal: true

require_relative '../../../test/test_helper'

class ProductTest < RailsTestCase
  def test_create_product
    product = Product.create!(name: 'Widget', price_cents: 1999)
    assert_equal 'Widget', product.name
    assert_equal 1999, product.price_cents
  end

  def test_name_required
    product = Product.new(price_cents: 100)
    refute product.valid?
    assert_includes product.errors[:name], "can't be blank"
  end

  def test_price_cents_must_be_positive
    product = Product.new(name: 'Widget', price_cents: 0)
    refute product.valid?
  end

  def test_price_formatting
    product = Product.new(name: 'Widget', price_cents: 1999)
    assert_equal '$19.99', product.price
  end

  def test_inventory_checker_accessible_internally
    product = Product.create!(name: 'Widget', price_cents: 100)
    assert InventoryChecker.in_stock?(product)
  end
end
