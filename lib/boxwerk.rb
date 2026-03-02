# frozen_string_literal: true

require_relative 'boxwerk/autoloader_mixin'
require_relative 'boxwerk/box_manager'
require_relative 'boxwerk/cli'
require_relative 'boxwerk/constant_resolver'
require_relative 'boxwerk/gem_resolver'
require_relative 'boxwerk/gemfile_require_parser'
require_relative 'boxwerk/global_context'
require_relative 'boxwerk/package'
require_relative 'boxwerk/package_context'
require_relative 'boxwerk/package_resolver'
require_relative 'boxwerk/privacy_checker'
require_relative 'boxwerk/setup'
require_relative 'boxwerk/version'
require_relative 'boxwerk/zeitwerk_scanner'

# Boxwerk is a package isolation system for Ruby applications built on
# Ruby::Box. It loads each package in its own +Ruby::Box+, enforcing
# dependency and privacy boundaries declared in +package.yml+ files.
module Boxwerk
  class << self
    # Returns the {PackageContext} for the currently executing package.
    # Each package box overrides this method via +BOXWERK_PACKAGE+.
    # Returns +nil+ in the root box.
    # @return [PackageContext, nil]
    def package
      nil
    end

    # Returns the {GlobalContext} for the root box.
    # @return [GlobalContext]
    def global
      Ruby::Box.root.const_get(:BOXWERK_GLOBAL)
    end
  end
end
