# frozen_string_literal: true

require 'zeitwerk'

require_relative 'boxwerk/box_manager'
require_relative 'boxwerk/cli'
require_relative 'boxwerk/constant_resolver'
require_relative 'boxwerk/folder_privacy_checker'
require_relative 'boxwerk/gem_resolver'
require_relative 'boxwerk/layer_checker'
require_relative 'boxwerk/package_resolver'
require_relative 'boxwerk/privacy_checker'
require_relative 'boxwerk/setup'
require_relative 'boxwerk/version'
require_relative 'boxwerk/visibility_checker'

module Boxwerk
  # Shared Zeitwerk inflector for consistent file→constant name mapping.
  def self.inflector
    @inflector ||= Zeitwerk::Inflector.new
  end
end
