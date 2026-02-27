# frozen_string_literal: true

require 'yaml'
require 'pathname'

module Boxwerk
  # Discovers packages by scanning for package.yml files and provides
  # topological ordering for boot.
  class PackageResolver
    attr_reader :packages, :root

    def initialize(root_path)
      @root_path = File.expand_path(root_path)
      @packages = {}

      discover_packages
      validate_no_cycles
    end

    # Returns packages in topological order (dependencies before dependents).
    def topological_order
      visited = {}
      order = []
      @packages.each_value { |pkg| visit(pkg, visited, order) }
      order
    end

    # Returns the direct dependency Package objects for a given package.
    def direct_dependencies(package)
      package.dependencies.filter_map { |dep_name| @packages[dep_name] }
    end

    private

    def discover_packages
      yml_paths = find_package_ymls

      yml_paths.each do |yml_path|
        package = Package.from_yml(yml_path, root_path: @root_path)
        @packages[package.name] = package
        @root = package if package.root?
      end

      @root ||= @packages['.']
    end

    def find_package_ymls
      ymls = []

      # Always include main package.yml
      root_yml = File.join(@root_path, 'package.yml')
      ymls << root_yml if File.exist?(root_yml)

      # Glob for all package.yml files in subdirectories
      Dir.glob(File.join(@root_path, '**', 'package.yml')).each do |path|
        next if path == root_yml
        ymls << path
      end

      ymls.uniq
    end

    def validate_no_cycles
      @packages.each_value do |pkg|
        detect_cycle(pkg, [])
      end
    end

    def detect_cycle(package, path)
      if path.include?(package.name)
        cycle = (path[path.index(package.name)..] + [package.name]).join(' -> ')
        raise "Circular dependency detected: #{cycle}"
      end

      package.dependencies.each do |dep_name|
        dep = @packages[dep_name]
        next unless dep

        detect_cycle(dep, path + [package.name])
      end
    end

    def visit(package, visited, order)
      return if visited[package.name]

      visited[package.name] = true
      package.dependencies.each do |dep_name|
        dep = @packages[dep_name]
        visit(dep, visited, order) if dep
      end
      order << package
    end
  end
end
