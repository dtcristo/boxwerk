# frozen_string_literal: true

require 'yaml'
require 'packwerk'

module Boxwerk
  # Discovers packages via Packwerk's PackageSet and provides
  # topological ordering for boot. Derives namespace names using
  # Zeitwerk conventions (e.g., packages/tax_calc → TaxCalc).
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

    # Derives the module namespace name from a package name/path.
    # e.g., "packages/finance" -> "Finance", "packages/tax_calc" -> "TaxCalc"
    def self.namespace_for(package_name)
      return nil if package_name == '.'

      basename = File.basename(package_name)
      Boxwerk.inflector.camelize(basename, nil)
    end

    # Returns the direct dependency Package objects for a given package.
    def direct_dependencies(package)
      package.dependencies.filter_map { |dep_name| @packages[dep_name] }
    end

    private

    def discover_packages
      package_set = Packwerk::PackageSet.load_all_from(@root_path)
      package_set.each do |packwerk_package|
        @packages[packwerk_package.name] = packwerk_package
        @root = packwerk_package if packwerk_package.root?
      end

      @root ||= @packages['.']
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
