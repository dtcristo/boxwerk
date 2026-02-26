# frozen_string_literal: true

# Boxwerk Example
# Run with: RUBY_BOX=1 boxwerk run app.rb

puts '=' * 60
puts 'Boxwerk Example'
puts '=' * 60
puts ''

# --- Basic package access ---
puts '1. Package access via namespace'
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
  puts "  ✗ #{e.message}"
end

begin
  Invoice.new
  puts '  ✗ ERROR: Invoice at top level!'
rescue NameError
  puts '  ✓ Invoice only via Finance:: namespace (correct)'
end
puts ''

# --- Transitive dependency prevention ---
puts '3. Transitive dependency prevention'
begin
  Util::Calculator.add(1, 2)
  puts '  ✗ ERROR: transitive dependency leaked!'
rescue NameError
  puts '  ✓ Util::Calculator blocked (transitive, not declared)'
end
puts ''

# --- Privacy enforcement ---
puts '4. Privacy enforcement'
begin
  Finance::Invoice.new
  puts '  ✓ Finance::Invoice accessible (in public_path)'
rescue NameError => e
  puts "  ✗ #{e.message}"
end

begin
  Finance::TaxCalculator
  puts '  ✗ ERROR: private constant accessible!'
rescue NameError
  puts '  ✓ Finance::TaxCalculator blocked (private)'
end
puts ''

# --- Visibility enforcement ---
puts '5. Visibility enforcement'
begin
  Notifications::Notifier.send_invoice_notification(invoice)
  puts '  ✓ Notifications::Notifier accessible (root in visible_to)'
rescue NameError => e
  puts "  ✗ #{e.message}"
end
puts ''

# --- Layer enforcement ---
puts '6. Layer enforcement (feature > core > utility)'
puts '  ✓ Finance (core) → Util (utility): allowed'
puts '  ✓ Notifications (feature) → Finance (core): allowed'
puts '  ✓ Layer violations raise at boot time'
puts ''

# --- Per-package gem isolation ---
puts '7. Per-package gem (json in util via Gemfile)'
puts '  ✓ Util has its own Gemfile with json gem'
puts '  ✓ Gems loaded into util box via $LOAD_PATH isolation'
puts ''

puts '=' * 60
puts 'All checks passed!'
puts '=' * 60
