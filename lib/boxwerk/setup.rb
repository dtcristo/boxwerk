# frozen_string_literal: true

module Boxwerk
  # Finds the root package.yml directory and boots all packages.
  module Setup
    class << self
      def run(start_dir: Dir.pwd)
        root_path = find_root(start_dir)
        unless root_path
          raise 'Cannot find boxwerk.yml or package.yml in current directory or ancestors'
        end

        # Run global boot in root box (after gems, before package boxes).
        run_global_boot(root_path)

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

      # Finds the project root directory. Looks for boxwerk.yml or
      # package.yml in the directory tree.
      def find_root(start_dir)
        current = File.expand_path(start_dir)
        loop do
          return current if File.exist?(File.join(current, 'boxwerk.yml'))
          return current if File.exist?(File.join(current, 'package.yml'))

          parent = File.dirname(current)
          break if parent == current

          current = parent
        end
        nil
      end

      # Runs the optional global boot in the root box. If a global/
      # directory exists, its files are autoloaded in the root box first.
      # Then global/boot.rb is required in the root box. This runs after
      # global gems are loaded but before package boxes are created, so
      # definitions here are inherited by all boxes.
      def run_global_boot(root_path)
        root_box = Ruby::Box.root
        global_dir = File.join(root_path, 'global')
        boot_script = File.join(global_dir, 'boot.rb')

        # Autoload global/ files in root box
        if File.directory?(global_dir)
          entries = ZeitwerkScanner.scan(global_dir)
          ZeitwerkScanner.register_autoloads(root_box, entries)
        end

        # Run global/boot.rb in root box
        root_box.require(boot_script) if File.exist?(boot_script)
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
