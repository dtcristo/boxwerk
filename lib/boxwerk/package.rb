# frozen_string_literal: true

module Boxwerk
  # Simple data class representing a package. Replaces Packwerk::Package
  # so that Boxwerk can work standalone without the Packwerk gem.
  # Reads the same package.yml format that Packwerk defines.
  class Package
    attr_reader :name, :config

    def initialize(name:, config: {})
      @name = name
      @config = config
    end

    def root?
      @name == '.'
    end

    def dependencies
      @config['dependencies'] || []
    end

    def enforce_dependencies?
      @config['enforce_dependencies'] == true
    end

    def ==(other)
      other.is_a?(Package) && name == other.name
    end

    alias eql? ==

    def hash
      name.hash
    end

    def to_s
      name
    end

    def inspect
      "#<Boxwerk::Package #{name}>"
    end

    # Loads a Package from a package.yml file.
    # The name is the relative path from root_path to the package directory.
    def self.from_yml(yml_path, root_path:)
      config = YAML.safe_load_file(yml_path) || {}
      pkg_dir = File.dirname(yml_path)
      name = if File.expand_path(pkg_dir) == File.expand_path(root_path)
               '.'
             else
               relative_path(pkg_dir, root_path)
             end
      new(name: name, config: config)
    end

    def self.relative_path(path, base)
      Pathname.new(File.expand_path(path))
              .relative_path_from(Pathname.new(File.expand_path(base)))
              .to_s
    end
  end
end
