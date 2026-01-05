# frozen_string_literal: true

module Boxwerk
  # Setup finds the root package, builds the dependency graph, and boots all packages.
  # Orchestrates the entire Boxwerk initialization process.
  module Setup
    class << self
      def run!(start_dir: Dir.pwd)
        root_path = find_package_yml(start_dir)
        raise 'Cannot find package.yml in current directory or ancestors' unless root_path

        graph = Boxwerk::Graph.new(root_path)
        registry = Boxwerk::Registry.new
        Boxwerk::Loader.boot_all(graph, registry)

        @graph = graph
        @booted = true
        graph
      end

      def graph
        @graph
      end

      def booted?
        @booted || false
      end

      def reset!
        @graph = nil
        @booted = false
      end

      private

      def find_package_yml(start_dir)
        current = File.expand_path(start_dir)
        loop do
          return current if File.exist?(File.join(current, 'package.yml'))

          parent = File.dirname(current)
          break if parent == current

          current = parent
        end
        nil
      end
    end
  end
end
