# frozen_string_literal: true

puts ''
puts Config::SHOP_NAME.colorize(:yellow).bold
puts '─' * 40

# Build the menu
latte = Menu::Item.new(name: 'Latte', price_cents: 550)
espresso = Menu::Item.new(name: 'Espresso', price_cents: 350)
muffin =
  Menu::Item.new(name: 'Blueberry Muffin', price_cents: 425, category: :food)

# Place an order
order = Orders::Order.new
order.add(latte, quantity: 2)
order.add(espresso)
order.add(muffin)

puts ''
puts '── Order ──'.colorize(:cyan).bold
puts order.summary
puts ''

# Loyalty card
card = Loyalty::Card.new
card.earn(order.total_cents)
puts '── Loyalty ──'.colorize(:cyan).bold
puts "  #{card}"
puts ''

# Kitchen
barista = Kitchen::Barista.new
puts '── Kitchen ──'.colorize(:cyan).bold
puts "  #{barista.prepare(latte)}"

# Stats (relaxed deps — reads global data stores without declaring dependencies)
Stats::Summary.print

# Faker version isolation
puts ''
puts '── Gem Isolation ──'.colorize(:cyan).bold
puts "  Loyalty faker:  v#{Loyalty::Card.faker_version}".colorize(:light_blue)
puts "  Kitchen faker:  v#{Kitchen::Barista.faker_version}".colorize(:light_blue)
puts ''
