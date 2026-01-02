# frozen_string_literal: true

module Boxwerk
  # Builds and validates the package dependency graph
  class Graph
    attr_reader :packages, :root

    def initialize(root_path)
      @root_path = root_path
      @packages = {}
      @root = load_package('root', root_path)
      resolve_dependencies(@root)
      validate!
    end

    # Returns packages in topological order (leaves first)
    def topological_order
      visited = {}
      order = []

      @packages.each_value { |package| visit(package, visited, order, []) }

      order
    end

    private

    # Validate that the graph is acyclic
    def validate!
      visited = {}
      rec_stack = {}

      @packages.each_value do |package|
        if has_cycle?(package, visited, rec_stack, [])
          raise 'Circular dependency detected in package graph'
        end
      end

      true
    end

    def load_package(name, path)
      return @packages[name] if @packages[name]

      package = Package.new(name, path)
      @packages[name] = package
      package
    end

    def resolve_dependencies(package)
      package.dependencies.each do |dep_path|
        dep_name = File.basename(dep_path)
        full_path = File.join(@root_path, dep_path)

        dep_package = load_package(dep_name, full_path)
        resolve_dependencies(dep_package)
      end
    end

    # DFS for topological sort
    def visit(package, visited, order, path)
      return if visited[package.name]

      if path.include?(package.name)
        raise "Circular dependency: #{(path + [package.name]).join(' -> ')}"
      end

      visited[package.name] = true

      package.dependencies.each do |dep_path|
        dep_name = File.basename(dep_path)
        dep_package = @packages[dep_name]
        visit(dep_package, visited, order, path + [package.name]) if dep_package
      end

      order << package
    end

    # Cycle detection
    def has_cycle?(package, visited, rec_stack, path)
      return false if visited[package.name]

      return true if rec_stack[package.name]

      visited[package.name] = true
      rec_stack[package.name] = true

      package.dependencies.each do |dep_path|
        dep_name = File.basename(dep_path)
        dep_package = @packages[dep_name]

        if dep_package &&
             has_cycle?(dep_package, visited, rec_stack, path + [package.name])
          return true
        end
      end

      rec_stack[package.name] = false
      false
    end
  end
end
