# frozen_string_literal: true

module Boxwerk
  # Setup orchestrates the Boxwerk boot process
  module Setup
    class << self
      # Main entry point for setup
      # @param start_dir [String] Directory to start searching for package.yml
      # @return [Boxwerk::Graph] The loaded and validated graph
      def run!(start_dir: Dir.pwd)
        # Find the root package.yml
        root_path = find_package_yml(start_dir)
        unless root_path
          raise 'Cannot find package.yml in current directory or ancestors'
        end

        # Build and validate dependency graph (happens automatically in constructor)
        graph = Boxwerk::Graph.new(root_path)

        # Create a registry instance for tracking booted packages
        registry = Boxwerk::Registry.new

        # Boot all packages in topological order (all in isolated boxes)
        Boxwerk::Loader.boot_all(graph, registry)

        # Store graph for introspection
        @graph = graph
        @booted = true

        graph
      end

      # Returns the loaded graph (for introspection)
      # @return [Boxwerk::Graph, nil]
      def graph
        @graph
      end

      # Check if Boxwerk has been booted
      # @return [Boolean]
      def booted?
        @booted || false
      end

      # Reset the setup state (useful for testing)
      def reset!
        @graph = nil
        @booted = false
      end

      private

      # Find package.yml by searching up the directory tree
      # @param start_dir [String] Directory to start searching from
      # @return [String, nil] Path to directory containing package.yml, or nil
      def find_package_yml(start_dir)
        current = File.expand_path(start_dir)
        loop do
          package_yml = File.join(current, 'package.yml')
          return current if File.exist?(package_yml)

          parent = File.dirname(current)
          break if parent == current # reached filesystem root

          current = parent
        end
        nil
      end
    end
  end
end
