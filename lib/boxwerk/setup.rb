# frozen_string_literal: true

module Boxwerk
  # Finds the root package.yml directory and boots all packages.
  module Setup
    class << self
      def run(start_dir: Dir.pwd)
        root_path = find_root(start_dir)
        unless root_path
          raise 'Cannot find package.yml in current directory or ancestors'
        end

        resolver = Boxwerk::PackageResolver.new(root_path)
        @box_manager = Boxwerk::BoxManager.new(root_path)
        @box_manager.boot_all(resolver)

        check_gem_conflicts(@box_manager.gem_resolver, resolver)

        @resolver = resolver
        @booted = true

        { resolver: resolver, box_manager: @box_manager, root_path: root_path }
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

      def reset
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

      def check_gem_conflicts(gem_resolver, package_resolver)
        conflicts = gem_resolver.check_conflicts(package_resolver)
        conflicts.each do |c|
          warn "Boxwerk: gem '#{c[:gem_name]}' is #{c[:package_version]} in #{c[:package]} " \
                 "but #{c[:global_version]} in global gems — both versions will be loaded into memory"
        end
      end
    end
  end
end
