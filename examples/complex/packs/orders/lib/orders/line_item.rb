# frozen_string_literal: true

module Orders
  class LineItem
    attr_reader :menu_item, :quantity

    def initialize(menu_item:, quantity:)
      @menu_item = menu_item
      @quantity = quantity
    end

    def total_cents
      menu_item.price_cents * quantity
    end

    def to_s
      "  #{quantity}x #{menu_item.name} @ #{menu_item.price} = #{format('$%.2f', total_cents / 100.0)}"
    end
  end
end
