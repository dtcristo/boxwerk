# frozen_string_literal: true

# Rails application configuration. Autoloaded in the root box
# before global/boot.rb runs.
module RailsApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = true
    config.api_only = true
    config.logger = Logger.new($stdout, level: :warn)

    # Disable Zeitwerk autoloading — Boxwerk handles it for packs
    config.autoload_paths = []
    config.eager_load_paths = []
  end
end
