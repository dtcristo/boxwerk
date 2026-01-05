# frozen_string_literal: true

module Boxwerk
  # Graph builds a directed acyclic graph (DAG) of package dependencies.
  # Validates no circular dependencies and provides topological ordering for boot sequence.
  class Graph
    attr_reader :packages, :root

    def initialize(root_path)
      @root_path = root_path
      @packages = {}
      @root = load_package('root', root_path)
      resolve_dependencies(@root, [])
    end

    def topological_order
      visited = {}
      order = []
      @packages.each_value { |pkg| visit(pkg, visited, order, []) }
      order
    end

    private

    def load_package(name, path)
      return @packages[name] if @packages[name]

      @packages[name] = Package.new(name, path)
    end

    def resolve_dependencies(package, path)
      raise "Circular dependency: #{(path + [package.name]).join(' -> ')}" if path.include?(package.name)

      package.dependencies.each do |dep_path|
        full_path = File.join(@root_path, dep_path)
        raise "Package not found: #{dep_path}" unless File.directory?(full_path)

        resolve_dependencies(load_package(File.basename(dep_path), full_path), path + [package.name])
      end
    end

    def visit(package, visited, order, path)
      return if visited[package.name]

      visited[package.name] = true
      package.dependencies.each do |dep_path|
        dep_package = @packages[File.basename(dep_path)]
        visit(dep_package, visited, order, path + [package.name]) if dep_package
      end
      order << package
    end
  end
end
