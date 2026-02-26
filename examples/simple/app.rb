# frozen_string_literal: true

# Boxwerk Example
# Run with: bundle exec boxwerk run app.rb

puts '=' * 60
puts 'Boxwerk Example'
puts '=' * 60
puts ''

# --- Basic package access ---
puts '1. Direct constant access from dependencies'
invoice = Invoice.new(tax_rate: 0.15)
invoice.add_item('Consulting', 100_000)
invoice.add_item('Design', 50_000)

puts "  Subtotal: #{invoice.subtotal}"
puts "  Tax: #{invoice.tax}"
puts "  Total: #{invoice.total}"
puts ''

# --- Dependency enforcement ---
puts '2. Dependency enforcement'
begin
  Invoice.new
  puts '  ✓ Invoice accessible (declared dependency on packs/finance)'
rescue NameError => e
  puts "  ✗ #{e.message}"
end
puts ''

# --- Transitive dependency prevention ---
puts '3. Transitive dependency prevention'
begin
  Calculator.add(1, 2)
  puts '  ✗ ERROR: transitive dependency leaked!'
rescue NameError
  puts '  ✓ Calculator blocked (transitive, not declared)'
end
puts ''

# --- Privacy enforcement ---
puts '4. Privacy enforcement'
begin
  Invoice.new
  puts '  ✓ Invoice accessible (in public/ path)'
rescue NameError => e
  puts "  ✗ #{e.message}"
end

begin
  TaxCalculator
  puts '  ✗ ERROR: private constant accessible!'
rescue NameError
  puts '  ✓ TaxCalculator blocked (private, not in public/ path)'
end
puts ''

# --- Per-package gem version isolation ---
puts '5. Per-package gem version isolation (faker)'
finance_version = Invoice.faker_version
greeting_version = Greeting.faker_version
puts "  packs/finance (via util) → Faker #{finance_version}"
puts "  packs/greeting           → Faker #{greeting_version}"
if finance_version != greeting_version
  puts '  ✓ Different faker versions running in isolated boxes!'
else
  puts '  ✗ ERROR: versions should differ!'
  exit 1
end
puts ''

puts '=' * 60
puts 'All checks passed!'
puts '=' * 60
