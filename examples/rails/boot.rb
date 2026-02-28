# frozen_string_literal: true

# Runs in the root box after global gems are loaded but before
# package boxes are created. Boots Rails in the root box so all
# Rails infrastructure is inherited by child boxes.

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'

# Load the application configuration (autoloaded from boot/)
RailsApp::Application.initialize!

puts "Rails #{Rails::VERSION::STRING} booted"
