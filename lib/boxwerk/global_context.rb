# frozen_string_literal: true

module Boxwerk
  # Runtime context for the global (root box) scope, accessible via
  # Boxwerk.global. Provides an autoloader for configuring additional
  # root box autoload directories from global/boot.rb or other code.
  class GlobalContext
    attr_reader :autoloader

    def initialize(root_path)
      @root_path = root_path
      @autoloader = Autoloader.new(root_path)
      @default_dirs = []
    end

    # Records a directory scanned by setup (e.g. global/) so it appears
    # in autoload info without needing to go through the autoloader.
    def record_scanned_dir(rel_path)
      @default_dirs << rel_path
    end

    # Returns dirs scanned by setup (not via autoloader push_dir).
    def default_dirs
      @default_dirs
    end

    # Returns dir info for the global context (used by the info command).
    def dir_info
      al_info = @autoloader&.dir_info || {}
      {
        autoload: @default_dirs + (al_info[:autoload] || []),
        collapse: al_info[:collapse] || [],
        ignore:   al_info[:ignore] || [],
      }
    end

    # Autoload configuration for the root box. Supports push_dir, collapse,
    # setup, and eager_load. Registrations happen lazily (autoload entries only)
    # until eager_load! is called. Constants are available via lazy autoload
    # throughout the boot process without requiring eager loading.
    class Autoloader
      def initialize(root_path)
        @root_path = root_path
        @autoload_dirs = []
        @collapse_dirs = []
        @ignore_dirs = []
        @setup_index = { push: 0, collapse: 0 }
        @accumulated_entries = []
      end

      # Returns dir info (used by GlobalContext#dir_info for the info command).
      def dir_info
        { autoload: @autoload_dirs.dup, collapse: @collapse_dirs.dup, ignore: @ignore_dirs.dup }
      end

      def push_dir(dir)
        @autoload_dirs << dir
        setup
      end

      def collapse(dir)
        @collapse_dirs << dir
        setup
      end

      def ignore(dir)
        @ignore_dirs << dir
      end

      # Register lazy autoloads for any dirs added since the last setup call.
      # Called automatically by push_dir/collapse so constants are available
      # via autoload in boot.rb without explicit setup. Does NOT eagerly require
      # files — call eager_load! to require all registered entries.
      def setup
        all_entries = []

        @autoload_dirs[@setup_index[:push]..].each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan(abs_dir))
        end
        @setup_index[:push] = @autoload_dirs.length

        @collapse_dirs[@setup_index[:collapse]..].each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir))
        end
        @setup_index[:collapse] = @collapse_dirs.length

        return if all_entries.empty?

        ZeitwerkScanner.register_autoloads(Ruby::Box.root, all_entries)
        @accumulated_entries.concat(all_entries)
      end

      # Eagerly require all files registered via push_dir/collapse so child
      # boxes inherit the constants (not just pending autoload entries).
      # Called after global/boot.rb when eager_load_global is true.
      def eager_load!
        return if @accumulated_entries.empty?

        root_box = Ruby::Box.root
        @accumulated_entries.each { |e| root_box.require(e.file) if e.file }
      end

      # Number of push_dir entries already registered via setup.
      def push_setup_count = @setup_index[:push]

      # Number of collapse entries already registered via setup.
      def collapse_setup_count = @setup_index[:collapse]
    end
  end
end
