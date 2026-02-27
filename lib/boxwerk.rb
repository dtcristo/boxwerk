# frozen_string_literal: true

require_relative 'boxwerk/box_manager'
require_relative 'boxwerk/cli'
require_relative 'boxwerk/constant_resolver'
require_relative 'boxwerk/gem_resolver'
require_relative 'boxwerk/package'
require_relative 'boxwerk/package_resolver'
require_relative 'boxwerk/privacy_checker'
require_relative 'boxwerk/setup'
require_relative 'boxwerk/version'

module Boxwerk
  # Converts a file path segment to a constant name using Zeitwerk conventions.
  # "tax_calculator" → "TaxCalculator", "api_v2" → "ApiV2"
  def self.camelize(basename)
    basename.split('_').map(&:capitalize).join
      .gsub(/(?<=\D)(\d)/) { $1 }
  end
end
