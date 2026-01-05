# frozen_string_literal: true

require 'yaml'

module Boxwerk
  # Package represents a single package loaded from package.yml.
  # Tracks exports, imports, dependencies, and the isolated Ruby::Box instance.
  class Package
    attr_reader :name, :path, :exports, :imports, :loaded_exports
    attr_accessor :box

    def initialize(name, path)
      @name = name
      @path = path
      @box = nil
      @exports = []
      @imports = []
      @loaded_exports = {}

      load_config
    end

    def booted?
      !@box.nil?
    end

    def dependencies
      @imports.map { |item| item.is_a?(String) ? item : item.keys.first }
    end

    private

    def load_config
      config_path = File.join(@path, 'package.yml')
      return unless File.exist?(config_path)

      config = YAML.load_file(config_path)
      @exports = config['exports'] || []
      @imports = config['imports'] || []
    end
  end
end
