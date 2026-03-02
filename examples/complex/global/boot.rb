# frozen_string_literal: true

# Runs in the global context after global gems are loaded but before
# package boxes are created. Use this for global initialization.

require 'dotenv/load'

puts "Booting #{Config::SHOP_NAME}..."

# Add extra root-level autoload dirs via Boxwerk.global.autoloader.
# Constants loaded here are available in all package boxes.
Boxwerk.global.autoloader.push_dir(File.expand_path('../lib', __dir__))
