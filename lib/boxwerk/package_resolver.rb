# frozen_string_literal: true

require 'yaml'
require 'pathname'

module Boxwerk
  # Discovers packages by scanning for package.yml files and provides
  # topological ordering for boot. Derives namespace names using
  # Zeitwerk conventions (e.g., packs/tax_calc -> TaxCalc).
  #
  # Reads packwerk.yml for package_paths and exclude configuration.
  # Does NOT require the Packwerk gem -- works standalone.
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
    # e.g., "packs/finance" -> "Finance", "packs/tax_calc" -> "TaxCalc"
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
      config = read_packwerk_config
      yml_paths = find_package_ymls(config)

      yml_paths.each do |yml_path|
        package = Package.from_yml(yml_path, root_path: @root_path)
        @packages[package.name] = package
        @root = package if package.root?
      end

      @root ||= @packages['.']
    end

    def read_packwerk_config
      config_path = File.join(@root_path, 'packwerk.yml')
      return {} unless File.exist?(config_path)

      YAML.safe_load_file(config_path) || {}
    end

    def find_package_ymls(config)
      exclude_patterns = config['exclude'] || []
      package_paths = config['package_paths'] || ['**/']

      ymls = []

      # Always include root package.yml
      root_yml = File.join(@root_path, 'package.yml')
      ymls << root_yml if File.exist?(root_yml)

      # Glob for package.yml files using package_paths patterns
      package_paths.each do |pattern|
        glob_pattern = if pattern.end_with?('/')
                         File.join(@root_path, pattern, 'package.yml')
                       elsif pattern.end_with?('package.yml')
                         File.join(@root_path, pattern)
                       else
                         File.join(@root_path, pattern, 'package.yml')
                       end

        Dir.glob(glob_pattern).each do |path|
          next if path == root_yml
          next if excluded?(path, exclude_patterns)

          ymls << path
        end
      end

      ymls.uniq
    end

    def excluded?(path, patterns)
      relative = Package.relative_path(path, @root_path)
      patterns.any? do |pattern|
        File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_DOTMATCH)
      end
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
