# frozen_string_literal: true

require 'colorize'

shop = ENV['SHOP_NAME'] || 'Coffee Shop'
puts shop.colorize(:yellow).bold

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
puts order.summary

# Loyalty card
card = Loyalty::Card.new
card.earn(order.total_cents)
puts "Loyalty: #{card}"

# Kitchen
barista = Kitchen::Barista.new
puts barista.prepare(latte)

# Faker version isolation
puts ''
puts "Loyalty faker: v#{Loyalty::Card.faker_version}".colorize(:cyan)
puts "Kitchen faker: v#{Kitchen::Barista.faker_version}".colorize(:cyan)
