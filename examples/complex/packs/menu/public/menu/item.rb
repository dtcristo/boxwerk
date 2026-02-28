# frozen_string_literal: true

module Menu
  class Item
    attr_reader :name, :price_cents, :category

    def initialize(name:, price_cents:, category: :drink)
      @name = name
      @price_cents = price_cents
      @category = category
      Menu.items << self
    end

    def price
      format("#{Config::CURRENCY}%.2f", price_cents / 100.0)
    end

    def to_s
      "#{name} (#{price})"
    end
  end
end
