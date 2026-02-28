# frozen_string_literal: true

# Root package boot — runs in root package box after global boot.
# Load and initialize the Rails application.

require_relative 'config/environment'

puts "Rails #{Rails::VERSION::STRING} booted"
