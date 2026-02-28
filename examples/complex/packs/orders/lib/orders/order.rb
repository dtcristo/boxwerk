# frozen_string_literal: true
# pack_public: true

module Orders
  class Order
    attr_reader :items

    def initialize
      @items = []
      Orders.orders << self
    end

    def add(menu_item, quantity: 1)
      @items << LineItem.new(menu_item: menu_item, quantity: quantity)
      self
    end

    def total_cents
      @items.sum(&:total_cents)
    end

    def total
      format("#{Config::CURRENCY}%.2f", total_cents / 100.0)
    end

    def summary
      lines = @items.map(&:to_s)
      lines << "Total: #{total}"
      lines.join("\n")
    end
  end
end
