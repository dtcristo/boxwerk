# frozen_string_literal: true

# Boot Rails in the root box. Runs after global gems are loaded.
# Application class is autoloaded from global/application.rb.

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'

Application.initialize!

puts "Rails #{Rails::VERSION::STRING} booted"
