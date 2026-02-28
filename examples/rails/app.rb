# frozen_string_literal: true

# Seed data and demonstrate cross-package constant resolution.

# Run migrations
ActiveRecord::MigrationContext.new(File.join(__dir__, 'db', 'migrate')).migrate

# Create records using models from different packages
alice = User.create!(name: 'Alice', email: 'alice@example.com')
product = Product.create!(name: 'Widget', price_cents: 1999)
order = Order.create!(user: alice, product: product, quantity: 3)

puts "User: #{alice.name} (#{alice.email})"
puts "Product: #{product.name} (#{product.price})"
puts "Order: #{order.quantity}x #{order.product.name} = $#{format('%.2f', order.total_cents / 100.0)}"
puts "Order user: #{order.user.name}"

# Verify privacy enforcement
begin
  UserValidator
  puts 'ERROR: UserValidator should be private!'
  exit 1
rescue NameError => e
  puts "Privacy enforced: #{e.message}"
end

puts 'Rails example OK'
