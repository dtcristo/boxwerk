# frozen_string_literal: true

require_relative 'boxwerk/box_manager'
require_relative 'boxwerk/cli'
require_relative 'boxwerk/constant_resolver'
require_relative 'boxwerk/gem_resolver'
require_relative 'boxwerk/gemfile_require_parser'
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
    # Available during boot.rb and at runtime inside a package box.
    # Returns nil outside a package context.
    def package
      Thread.current[:boxwerk_package_context]
    end

    def package=(context)
      Thread.current[:boxwerk_package_context] = context
    end
  end
end
