# frozen_string_literal: true

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'

class Application < Rails::Application
  config.load_defaults 8.1
  config.eager_load = true
  config.api_only = true
  config.logger = Logger.new($stdout, level: :warn)

  # Boxwerk handles autoloading for packs
  config.autoload_paths = []
  config.eager_load_paths = []
end
