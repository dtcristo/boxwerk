# frozen_string_literal: true

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

module Boxwerk
  class << self
    # Returns the PackageContext for the current package.
    # Each package box overrides this method to return its own
    # BOXWERK_PACKAGE constant. Returns nil in root box or outside
    # a package context.
    def package
      nil
    end

    # Returns the GlobalContext for the root box.
    # Set during Setup.run and available in global/boot.rb and elsewhere.
    def global
      @global_context
    end

    # Sets the GlobalContext (called by Setup.run).
    def global=(ctx)
      @global_context = ctx
    end
  end
end
