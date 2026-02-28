# frozen_string_literal: true

module Example
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.eager_load = false
  end
end
