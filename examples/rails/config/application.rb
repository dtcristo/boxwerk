# frozen_string_literal: true

# Rails frameworks are loaded in global/boot.rb.
# Guard against re-definition when loaded from different box contexts.

unless Rails.application
  module Example
    class Application < Rails::Application
      config.load_defaults 8.1
      config.eager_load = true
      config.api_only = true
      config.logger = Logger.new($stdout, level: :warn)

      # Boxwerk handles autoloading for packs
      config.autoload_paths = []
      config.eager_load_paths = []
    end
  end
end
