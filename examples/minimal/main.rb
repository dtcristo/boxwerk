# frozen_string_literal: true

# Boxwerk Minimal Example

puts "Foo: #{Foo.call}"
puts "Bar: #{Bar.call}"

# Bar depends on Baz, so Bar can access Baz
puts "Bar uses Baz: #{Bar.baz_call}"

# Baz is NOT a direct dependency of root — blocked
begin
  Baz.call
  abort 'ERROR: Baz should not be accessible'
rescue NameError
  puts 'Baz: blocked (transitive dependency)'
end
