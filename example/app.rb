# frozen_string_literal: true

# Example Boxwerk Application
# Run with: RUBY_BOX=1 boxwerk app.rb

puts '=' * 70
puts 'Boxwerk Application'
puts '=' * 70
puts ''

puts 'Creating invoice...'
invoice = Finance::Invoice.new(tax_rate: 0.15)
invoice.add_item('Web Development', 200_000) # $2000.00 in cents
invoice.add_item('Design Work', 150_000) # $1500.00 in cents
invoice.add_item('Consulting', 80_000) # $800.00 in cents

data = invoice.to_h

puts "\nInvoice Details:"
data[:items].each_with_index do |item, i|
  amount_dollars = item[:amount] / 100.0
  puts "  #{i + 1}. #{item[:description]}: $#{format('%.2f', amount_dollars)}"
end
puts ''
puts "  Subtotal: $#{format('%.2f', data[:subtotal] / 100.0)}"
puts "  Tax (15%): $#{format('%.2f', data[:tax] / 100.0)}"
puts "  Total: $#{format('%.2f', data[:total] / 100.0)}"
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

# UtilCalculator should NOT be available (transitive dependency)
begin
  UtilCalculator.add(1, 2)
  puts '  ✗ ERROR: UtilCalculator leaked from transitive dependency!'
rescue NameError
  puts '  ✓ UtilCalculator not accessible (correct isolation)'
end

# Invoice should NOT be at top level (only in Finance namespace)
begin
  Invoice.new
  puts '  ✗ ERROR: Invoice available at top level!'
rescue NameError
  puts '  ✓ Invoice only accessible via Finance namespace'
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

puts ''
puts '=' * 70
puts '✓ Application completed successfully'
puts '=' * 70
puts ''
puts 'Boxwerk CLI setup process:'
puts '  1. `boxwerk run app.rb` found root package.yml'
puts '  2. Built dependency graph (util → finance → root)'
puts '  3. Validated no circular dependencies'
puts '  4. Booted packages in topological order (all in isolated boxes)'
puts '  5. Executed app.rb in root package box with Finance imported'
puts ''
puts 'Key difference: ALL packages (including root) run in isolated boxes.'
puts 'The main Ruby process only contains gems and the Boxwerk runtime.'
puts ''
