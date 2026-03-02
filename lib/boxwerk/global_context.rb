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
    end

    # Autoload configuration for the root box. Supports push_dir, collapse,
    # and setup. Registrations happen immediately in Ruby::Box.root so
    # constants are available throughout the boot process.
    class Autoloader
      attr_reader :autoload_dirs, :collapse_dirs

      def initialize(root_path)
        @root_path = root_path
        @autoload_dirs = []
        @collapse_dirs = []
        @setup_index = { push: 0, collapse: 0 }
      end

      def push_dir(dir)
        @autoload_dirs << dir
        setup
      end

      def collapse(dir)
        @collapse_dirs << dir
        setup
      end

      # Immediately register autoloads for any dirs added since the last
      # setup call. Called automatically by push_dir/collapse, but can also
      # be called explicitly to force eager loading of registered dirs.
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

        root_box = Ruby::Box.root
        ZeitwerkScanner.register_autoloads(root_box, all_entries)
        # Also require each file eagerly so child boxes inherit the constants
        all_entries.each { |e| root_box.require(e.file) if e.file }
      end

      # Number of push_dir entries already registered via setup.
      def push_setup_count = @setup_index[:push]

      # Number of collapse entries already registered via setup.
      def collapse_setup_count = @setup_index[:collapse]
    end
  end
end
