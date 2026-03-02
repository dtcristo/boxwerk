# frozen_string_literal: true

module Boxwerk
  # Finds the root package.yml directory and boots all packages.
  module Setup
    class << self
      def run(start_dir: Dir.pwd, packages: nil, config: {})
        root_path = find_root(start_dir)

        resolver = Boxwerk::PackageResolver.new(root_path, config_overrides: config)
        config = resolver.boxwerk_config
        eager_load_global = config.fetch('eager_load_global', true)
        eager_load_packages = config.fetch('eager_load_packages', false)

        # Create GlobalContext and expose it as Boxwerk.global before boot.rb runs
        global_context = GlobalContext.new(root_path)
        Boxwerk.global = global_context

        # Run global boot in root box (after gems, before package boxes).
        run_global_boot(root_path, eager_load: eager_load_global, global_context: global_context)

        # Eager-load all Zeitwerk-managed constants in root box so child
        # boxes inherit fully resolved constants (not pending autoloads).
        eager_load_zeitwerk if eager_load_global

        @box_manager = Boxwerk::BoxManager.new(root_path)
        if packages
          packages.each do |pkg|
            @box_manager.boot_package(
              pkg,
              resolver,
              eager_load_packages: eager_load_packages,
            )
          end
        else
          @box_manager.boot_all(
            resolver,
            eager_load_packages: eager_load_packages,
          )
        end

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
        Boxwerk.global = nil
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
      def run_global_boot(root_path, eager_load: true, global_context: nil)
        root_box = Ruby::Box.root
        global_dir = File.join(root_path, 'global')
        global_boot = File.join(global_dir, 'boot.rb')

        # Require global/ files in root box so they are defined before
        # child boxes are created (not just registered as autoloads).
        # Only when eager_load_global is true; global/boot.rb always runs.
        if eager_load && File.directory?(global_dir)
          entries = ZeitwerkScanner.scan(global_dir)
          entries.each do |entry|
            next unless entry.file && entry.file != global_boot
            root_box.require(entry.file)
          end
        end

        # Run global/boot.rb in root box (always, regardless of eager_load)
        root_box.require(global_boot) if File.exist?(global_boot)

        # After global/boot.rb, re-setup the global autoloader to pick up
        # any dirs added via Boxwerk.global.autoloader.push_dir during boot
        # that haven't been registered yet. Since push_dir auto-calls setup,
        # this is mainly a safety net for dirs added outside of push_dir.
        global_context&.autoloader&.setup
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
