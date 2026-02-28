# frozen_string_literal: true

# Boot Rails in the global context. Runs after global gems are loaded.
# All Rails infrastructure is inherited by package boxes.

require_relative '../config/application'
Application.initialize!

puts "Rails #{Rails::VERSION::STRING} booted"
