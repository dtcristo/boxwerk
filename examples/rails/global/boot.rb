# frozen_string_literal: true

# Global boot — runs in root box before package boxes are created.
# Require and eager load Rails frameworks so they are available in all boxes.

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'rails/command'

# Eager load Rails internals so child boxes inherit fully resolved constants.
# Boxwerk calls Zeitwerk::Loader.eager_load_all after this script, but the
# framework-specific eager_load! methods resolve non-Zeitwerk autoloads too.
ActiveSupport.eager_load!
ActiveRecord.eager_load!
ActionController.eager_load!
