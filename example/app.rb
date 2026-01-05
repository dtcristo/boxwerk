# frozen_string_literal: true

# Boxwerk Example
# Run with: RUBY_BOX=1 boxwerk app.rb

puts '=' * 70
puts 'Boxwerk Example'
puts '=' * 70
puts ''

puts 'Creating invoice...'
invoice = Finance::Invoice.new(tax_rate: 0.15)
invoice.add_item('Consulting', 100_000)
invoice.add_item('Design', 50_000)

puts "  Subtotal: #{invoice.subtotal}"
puts "  Tax: #{invoice.tax}"
puts "  Total: #{invoice.total}"
puts ''

puts 'Testing isolation...'
# Finance::Invoice should be available
begin
  test_invoice = Finance::Invoice.new
  puts '  ✓ Finance::Invoice accessible'
rescue NameError => e
  puts "  ✗ Finance::Invoice not accessible: #{e.message}"
end

# Finance::TaxCalculator should be available
begin
  Finance::TaxCalculator
  puts '  ✓ Finance::TaxCalculator accessible'
rescue NameError => e
  puts "  ✗ Finance::TaxCalculator not accessible: #{e.message}"
end

begin
  Invoice.new
  puts '  ✗ ERROR: Invoice available at top level!'
rescue NameError
  puts '  ✓ Invoice only accessible via Finance namespace'
end

# UtilCalculator should NOT be available (transitive dependency)
begin
  UtilCalculator.add(1, 2)
  puts '  ✗ ERROR: UtilCalculator leaked from transitive dependency!'
rescue NameError
  puts '  ✓ UtilCalculator not accessible (correct isolation)'
end

# Calculator should NOT be available (transitive dependency from util package)
begin
  Calculator.add(1, 2)
  puts '  ✗ ERROR: Calculator leaked from transitive dependency!'
rescue NameError
  puts '  ✓ Calculator not accessible (correct isolation)'
end

# Geometry should NOT be available (transitive dependency from util package)
begin
  Geometry.circle_area(5)
  puts '  ✗ ERROR: Geometry leaked from transitive dependency!'
rescue NameError
  puts '  ✓ Geometry not accessible (correct isolation)'
end

# Money gem SHOULD be accessible (gems are global, not isolated)
begin
  test_money = Money.new(100, 'USD')
  puts '  ✓ Money gem accessible (gems are global)'
rescue NameError => e
  puts "  ✗ ERROR: Money gem not accessible: #{e.message}"
end
