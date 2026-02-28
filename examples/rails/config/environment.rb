# frozen_string_literal: true

# This file exists for Rails compatibility (rails/commands expects it).
# Application initialization is handled by Boxwerk's boot.rb.

require_relative 'application'

# Rails.application is already set by boot.rb — skip re-initialization
Rails.application.initialize! unless Rails.application&.initialized?
