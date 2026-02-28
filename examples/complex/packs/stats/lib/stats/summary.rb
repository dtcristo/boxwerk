# frozen_string_literal: true

module Stats
  class Summary
    # Accesses Orders::Order and Config without declaring dependencies.
    # Works because enforce_dependencies is not enabled for this package.
    def self.for(order)
      "#{order.items.size} items, #{order.total} (#{Config::SHOP_NAME})"
    end
  end
end
