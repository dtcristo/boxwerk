# frozen_string_literal: true

require 'colorize'

module Stats
  class Summary
    def self.print
      puts ''
      puts '── Stats ──'.colorize(:magenta).bold
      puts "  Menu: #{Menu.items.size} items".colorize(:green)
      puts "  Orders: #{Orders.orders.size} placed".colorize(:green)
      puts "  Loyalty: #{Loyalty.cards.size} members".colorize(:green)

      if Orders.orders.any?
        total = Orders.orders.sum(&:total_cents)
        puts "  Revenue: #{format("#{Config::CURRENCY}%.2f", total / 100.0)}".colorize(
               :yellow,
             )
      end
    end
  end
end
