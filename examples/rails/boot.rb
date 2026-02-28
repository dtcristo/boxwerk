# frozen_string_literal: true

# Root package boot — runs in root package box after global boot.
# Initialize our Rails application here so it's ready for use.

require_relative 'config/application'
Example::Application.initialize!

puts "Rails #{Rails::VERSION::STRING} booted"
