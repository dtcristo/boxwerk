# frozen_string_literal: true

module Boxwerk
  # Finds the root package.yml directory and boots all packages.
  module Setup
    class << self
      def run(start_dir: Dir.pwd)
        root_path = find_root(start_dir)

        # Run global boot in root box (after gems, before package boxes).
        run_global_boot(root_path)

        # Eager-load all Zeitwerk-managed constants in root box so child
        # boxes inherit fully resolved constants (not pending autoloads).
        eager_load_zeitwerk

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

      # Finds the project root directory. Walks up the directory tree
      # looking for boxwerk.yml or package.yml. Falls back to start_dir
      # if neither is found (implicit root).
      def find_root(start_dir)
        current = File.expand_path(start_dir)
        loop do
          return current if File.exist?(File.join(current, 'boxwerk.yml'))
          return current if File.exist?(File.join(current, 'package.yml'))

          parent = File.dirname(current)
          break if parent == current

          current = parent
        end

        # Fall back to CWD as implicit root
        File.expand_path(start_dir)
      end

      # Runs the optional global boot in the root box. The global/
      # directory is autoloaded and global/boot.rb is required in the root
      # box. These run after global gems are loaded but before package
      # boxes are created, so definitions here are inherited by all boxes.
      #
      # Root-level boot.rb is NOT handled here — it runs in the root
      # package box via BoxManager (like any other package boot.rb).
      def run_global_boot(root_path)
        root_box = Ruby::Box.root
        global_dir = File.join(root_path, 'global')
        global_boot = File.join(global_dir, 'boot.rb')

        # Require global/ files in root box so they are defined before
        # child boxes are created (not just registered as autoloads).
        if File.directory?(global_dir)
          entries = ZeitwerkScanner.scan(global_dir)
          entries.each do |entry|
            next unless entry.file && entry.file != global_boot
            root_box.require(entry.file)
          end
        end

        # Run global/boot.rb in root box
        root_box.require(global_boot) if File.exist?(global_boot)
      end

      def check_gem_conflicts(gem_resolver, package_resolver)
        conflicts = gem_resolver.check_conflicts(package_resolver)
        conflicts.each do |c|
          warn "Boxwerk: gem '#{c[:gem_name]}' is #{c[:package_version]} in #{c[:package]} " \
                 "but #{c[:global_version]} in global gems — both versions will be loaded into memory"
        end
      end

      # Eager-load all Zeitwerk-managed constants (gem autoloads) in the root
      # box. Child boxes created via Ruby::Box.new inherit a snapshot of the
      # root box's constants. Zeitwerk autoloads are lazy — without eager
      # loading, child boxes inherit pending autoload entries that may not
      # resolve correctly across box boundaries.
      def eager_load_zeitwerk
        Ruby::Box.root.eval(<<~RUBY)
          Zeitwerk::Loader.eager_load_all if defined?(Zeitwerk)
        RUBY
      end
    end
  end
end
