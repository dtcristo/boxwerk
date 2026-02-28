# frozen_string_literal: true

# Global boot — runs in root box before package boxes are created.
# Rails classes are inherited by all package boxes.

require_relative '../config/application'
Example::Application.initialize!

puts "Rails #{Rails::VERSION::STRING} booted"
