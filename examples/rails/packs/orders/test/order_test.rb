# frozen_string_literal: true

require_relative '../../../test/test_helper'

class OrderTest < RailsTestCase
  def setup
    super
    @user = User.create!(name: 'Alice', email: 'alice@example.com')
    @product = Product.create!(name: 'Widget', price_cents: 1000)
  end

  def test_create_order
    order = Order.create!(user: @user, product: @product, quantity: 2)
    assert_equal 2, order.quantity
  end

  def test_belongs_to_user
    order = Order.create!(user: @user, product: @product, quantity: 1)
    assert_equal @user, order.user
  end

  def test_belongs_to_product
    order = Order.create!(user: @user, product: @product, quantity: 1)
    assert_equal @product, order.product
  end

  def test_quantity_must_be_positive
    order = Order.new(user: @user, product: @product, quantity: 0)
    refute order.valid?
  end

  def test_total_cents
    order = Order.create!(user: @user, product: @product, quantity: 3)
    assert_equal 3000, order.total_cents
  end

  def test_order_processor_accessible_internally
    order = Order.create!(user: @user, product: @product, quantity: 1)
    result = OrderProcessor.process(order)
    assert_includes result, 'Widget'
    assert_includes result, 'Alice'
  end
end
