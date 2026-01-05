# frozen_string_literal: true

require 'yaml'

module Boxwerk
  # Represents a package loaded from package.yml
  class Package
    attr_reader :name, :path, :exports, :imports, :box, :loaded_exports

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

    def box=(box_instance)
      @box = box_instance
    end

    def dependencies
      @imports.map do |item|
        if item.is_a?(String)
          item
        else
          item.keys.first
        end
      end
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
