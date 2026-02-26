# frozen_string_literal: true

module Boxwerk
  # Setup finds the root package.yml, discovers packages via Packwerk,
  # and boots all packages with Box isolation.
  module Setup
    class << self
      def run!(start_dir: Dir.pwd)
        root_path = find_root(start_dir)
        raise 'Cannot find package.yml in current directory or ancestors' unless root_path

        resolver = Boxwerk::PackageResolver.new(root_path)
        @box_manager = Boxwerk::BoxManager.new(root_path)
        @box_manager.boot_all(resolver)

        @resolver = resolver
        @booted = true

        { resolver: resolver, box_manager: @box_manager }
      end

      def resolver
        @resolver
      end

      def box_manager
        @box_manager
      end

      def booted?
        @booted || false
      end

      def root_box
        return nil unless @box_manager && @resolver&.root

        @box_manager.boxes[@resolver.root.name]
      end

      def reset!
        @resolver = nil
        @box_manager = nil
        @booted = false
      end

      private

      def find_root(start_dir)
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
