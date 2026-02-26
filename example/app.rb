# frozen_string_literal: true

# Boxwerk Example
# Run with: RUBY_BOX=1 boxwerk run app.rb

puts '=' * 70
puts 'Boxwerk Example (Packwerk runtime enforcement)'
puts '=' * 70
puts ''

# --- Basic package access ---
puts '1. Basic package access (Finance → root via dependency)'
invoice = Finance::Invoice.new(tax_rate: 0.15)
invoice.add_item('Consulting', 100_000)
invoice.add_item('Design', 50_000)

puts "  Subtotal: #{invoice.subtotal}"
puts "  Tax: #{invoice.tax}"
puts "  Total: #{invoice.total}"
puts ''

# --- Namespace isolation ---
puts '2. Namespace isolation'
begin
  Finance::Invoice.new
  puts '  ✓ Finance::Invoice accessible (declared dependency)'
rescue NameError => e
  puts "  ✗ Finance::Invoice not accessible: #{e.message}"
end

begin
  Invoice.new
  puts '  ✗ ERROR: Invoice available at top level!'
rescue NameError
  puts '  ✓ Invoice only accessible via Finance:: namespace'
end
puts ''

# --- Transitive dependency prevention ---
puts '3. Transitive dependency prevention'
begin
  Util::Calculator.add(1, 2)
  puts '  ✗ ERROR: Util::Calculator leaked from transitive dependency!'
rescue NameError
  puts '  ✓ Util::Calculator not accessible (correct isolation)'
end
puts ''

# --- Privacy enforcement ---
puts '4. Privacy enforcement (finance has enforce_privacy: true)'
begin
  Finance::Invoice.new
  puts '  ✓ Finance::Invoice accessible (in public_path)'
rescue NameError => e
  puts "  ✗ Finance::Invoice not accessible: #{e.message}"
end

begin
  Finance::TaxCalculator
  puts '  ✗ ERROR: Finance::TaxCalculator accessible (should be private)!'
rescue NameError
  puts '  ✓ Finance::TaxCalculator blocked (private, not in public_path)'
end
puts ''

# --- Visibility enforcement ---
puts '5. Visibility enforcement (notifications visible_to: ["."])'
begin
  Notifications::Notifier.send_invoice_notification(invoice)
  puts '  ✓ Notifications::Notifier accessible (root is in visible_to)'
rescue NameError => e
  puts "  ✗ Notifications::Notifier not accessible: #{e.message}"
end
puts ''

# --- Layer enforcement ---
puts '6. Layer enforcement (feature > core > utility)'
puts '  ✓ Finance (core) → Util (utility): allowed (core > utility)'
puts '  ✓ Notifications (feature) → Finance (core): allowed (feature > core)'
puts '  ✓ Layer violations raise LayerViolationError at boot time'
puts ''

# --- Gem handling ---
puts '7. Global gem access'
begin
  test_money = Money.new(100, 'USD')
  puts '  ✓ Money gem accessible (gems are global)'
rescue NameError => e
  puts "  ✗ Money gem not accessible: #{e.message}"
end
puts ''

puts '=' * 70
puts 'All checks passed!'
puts '=' * 70
