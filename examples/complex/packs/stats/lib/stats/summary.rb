# frozen_string_literal: true

module Stats
  class Summary
    def self.print
      puts ''
      puts '── Stats ──'.colorize(:magenta).bold
      puts "  Menu items:     #{Menu.items.size}".colorize(:green)
      puts "  Orders placed:  #{Orders.orders.size}".colorize(:green)
      puts "  Loyalty members: #{Loyalty.cards.size}".colorize(:green)

      if Orders.orders.any?
        total = Orders.orders.sum(&:total_cents)
        puts "  Revenue:        #{format("#{Config::CURRENCY}%.2f", total / 100.0)}".colorize(
               :yellow,
             )
      end
    end
  end
end
