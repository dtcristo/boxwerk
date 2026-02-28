# frozen_string_literal: true

require_relative 'test_helper'

class IntegrationTest < RailsTestCase
  def test_user_creation
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    assert_equal 'Alice', user.name
  end

  def test_product_creation
    product = Product.create!(name: 'Widget', price_cents: 1999)
    assert_equal 'Widget', product.name
  end

  def test_order_associations
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    product = Product.create!(name: 'Widget', price_cents: 1999)
    order = Order.create!(user: user, product: product, quantity: 3)
    assert_equal user, order.user
    assert_equal product, order.product
  end

  def test_order_total_cents
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    product = Product.create!(name: 'Widget', price_cents: 1000)
    order = Order.create!(user: user, product: product, quantity: 5)
    assert_equal 5000, order.total_cents
  end

  def test_application_record_accessible
    assert ApplicationRecord
  end

  # Privacy enforcement — private constants not accessible from root
  def test_user_validator_is_private
    assert_raises(NameError) { UserValidator }
  end

  def test_inventory_checker_is_private
    assert_raises(NameError) { InventoryChecker }
  end

  def test_order_processor_is_private
    assert_raises(NameError) { OrderProcessor }
  end
end
