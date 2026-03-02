# frozen_string_literal: true

module Boxwerk
  # Runtime context for the current package, accessible via Boxwerk.package.
  # Provides metadata and configuration for the package that owns the
  # currently executing code.
  class PackageContext
    attr_reader :name, :root_path, :autoloader

    def initialize(name:, root_path:, config:, autoloader:)
      @name = name
      @root_path = root_path
      @config = config.freeze
      @autoloader = autoloader
    end

    def root?
      @name == '.'
    end

    def config
      @config
    end

    # Lightweight autoload configuration object. Provides the same interface
    # as Zeitwerk::Loader for push_dir, collapse, and ignore — but only
    # collects configuration. Actual autoload registration is handled by
    # BoxManager via ZeitwerkScanner.
    #
    # Autoload registration happens immediately when push_dir or collapse
    # is called from within boot.rb, making added constants available for
    # use later in the same script. Explicit `setup` calls are not required.
    #
    # autoload_dirs/collapse_dirs/ignore_dirs return default dirs (lib/, public/)
    # first, followed by any dirs added via push_dir/collapse/ignore in boot.rb.
    class Autoloader
      def initialize(root_path, box: nil)
        @root_path = root_path
        @box = box
        @default_autoload_dirs = []
        @default_collapse_dirs = []
        @default_ignore_dirs = []
        @user_autoload_dirs = []
        @user_collapse_dirs = []
        @user_ignore_dirs = []
        @setup_index = { push: 0, collapse: 0 }
      end

      # Called by BoxManager after scanning to inject default dirs.
      def set_defaults(autoload_dirs: [], collapse_dirs: [], ignore_dirs: [])
        @default_autoload_dirs = autoload_dirs
        @default_collapse_dirs = collapse_dirs
        @default_ignore_dirs = ignore_dirs
      end

      def autoload_dirs = @default_autoload_dirs + @user_autoload_dirs
      def collapse_dirs = @default_collapse_dirs + @user_collapse_dirs
      def ignore_dirs   = @default_ignore_dirs + @user_ignore_dirs

      # All collapse dirs (default + user) for cleanup after boot.rb
      def all_collapse_dirs = @default_collapse_dirs + @user_collapse_dirs

      # For internal use by BoxManager — only user-added dirs (not defaults).
      def user_autoload_dirs = @user_autoload_dirs
      def user_collapse_dirs = @user_collapse_dirs
      def user_ignore_dirs   = @user_ignore_dirs

      def push_dir(dir)
        @user_autoload_dirs << dir
        setup
      end

      def collapse(dir)
        @user_collapse_dirs << dir
        setup
      end

      def ignore(dir)
        @user_ignore_dirs << dir
      end

      # Immediately scan and register autoloads for any dirs added via
      # push_dir or collapse since the last setup call (or the beginning).
      # Called automatically by push_dir/collapse so constants are available
      # immediately in boot.rb without an explicit setup call.
      def setup
        return unless @box

        all_entries = []

        @user_autoload_dirs[@setup_index[:push]..].each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan(abs_dir))
        end
        @setup_index[:push] = @user_autoload_dirs.length

        @user_collapse_dirs[@setup_index[:collapse]..].each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          root_dir = find_root_for(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir, root_dir: root_dir))
        end
        @setup_index[:collapse] = @user_collapse_dirs.length

        return if all_entries.empty?

        ZeitwerkScanner.register_autoloads(@box, all_entries)
        file_index = ZeitwerkScanner.build_file_index(all_entries)
        # Accumulate entries so apply_boot_config can merge into file_indexes
        @accumulated_file_index ||= {}
        @accumulated_file_index.merge!(file_index)
        file_index
      end

      # Returns file index accumulated from all setup calls (for BoxManager).
      def accumulated_file_index
        @accumulated_file_index || {}
      end

      # Number of push_dir entries already registered via setup.
      def push_setup_count = @setup_index[:push]

      # Number of collapse entries already registered via setup.
      def collapse_setup_count = @setup_index[:collapse]

      # Returns the absolute root autoload dir that contains abs_dir, or nil.
      def find_root_for(abs_dir)
        (@default_autoload_dirs + @user_autoload_dirs)
          .map { |d| File.expand_path(d, @root_path) }
          .find { |root| abs_dir.start_with?("#{root}/") }
      end
    end
  end
end
