# frozen_string_literal: true

# Runs in the global context after global gems are loaded but before
# package boxes are created. Use this for global initialization.

require 'dotenv/load'

puts "Booting #{Config::SHOP_NAME}..."
