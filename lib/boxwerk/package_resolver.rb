# frozen_string_literal: true

require 'yaml'
require 'pathname'

module Boxwerk
  # Discovers packages by scanning for package.yml files and provides
  # ordering for boot. Supports boxwerk.yml configuration for package_paths.
  class PackageResolver
    attr_reader :packages, :root

    def initialize(root_path)
      @root_path = File.expand_path(root_path)
      @packages = {}
      @config = load_boxwerk_config

      discover_packages
    end

    # Returns packages in boot order. Dependencies come before dependents
    # when possible. Circular dependencies are allowed — strongly connected
    # components are grouped together.
    def topological_order
      visited = {}
      order = []
      @packages.each_value { |pkg| visit(pkg, visited, order, Set.new) }
      order
    end

    # Returns the direct dependency Package objects for a given package.
    def direct_dependencies(package)
      package.dependencies.filter_map { |dep_name| @packages[dep_name] }
    end

    # Returns all packages except the given one.
    def all_except(package)
      @packages.values.reject { |p| p.name == package.name }
    end

    # Boxwerk configuration from boxwerk.yml.
    def boxwerk_config
      @config
    end

    private

    def load_boxwerk_config
      yml_path = File.join(@root_path, 'boxwerk.yml')
      if File.exist?(yml_path)
        YAML.safe_load_file(yml_path) || {}
      else
        {}
      end
    end

    def discover_packages
      yml_paths = find_package_ymls

      yml_paths.each do |yml_path|
        package = Package.from_yml(yml_path, root_path: @root_path)
        @packages[package.name] = package
        @root = package if package.root?
      end

      # Implicit root package if no package.yml at root
      unless @root
        @root = Package.implicit_root(@packages.keys)
        @packages['.'] = @root
      end
    end

    def find_package_ymls
      ymls = []

      # Check for root package.yml
      root_yml = File.join(@root_path, 'package.yml')
      ymls << root_yml if File.exist?(root_yml)

      # Use package_paths from boxwerk.yml (default: ["**/"])
      package_paths = @config['package_paths'] || ['**/']

      package_paths.each do |pattern|
        glob = File.join(@root_path, pattern, 'package.yml')
        Dir
          .glob(glob)
          .each do |path|
            next if path == root_yml
            ymls << path
          end
      end

      ymls.uniq
    end

    def visit(package, visited, order, in_stack)
      return if visited[package.name]

      visited[package.name] = true
      in_stack.add(package.name)

      package.dependencies.each do |dep_name|
        dep = @packages[dep_name]
        next unless dep
        # Skip back-edges (cycles) — they'll be handled naturally
        next if in_stack.include?(dep_name)
        visit(dep, visited, order, in_stack)
      end

      in_stack.delete(package.name)
      order << package
    end
  end
end
