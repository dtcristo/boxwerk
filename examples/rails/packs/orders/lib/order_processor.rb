# frozen_string_literal: true

# Private: internal order processing logic.
class OrderProcessor
  def self.process(order)
    "Order ##{order.id}: #{order.quantity}x #{order.product.name} for #{order.user.name}"
  end
end
