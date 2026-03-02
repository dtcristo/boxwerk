# frozen_string_literal: true

module Boxwerk
  # Runtime context for the current package, accessible via +Boxwerk.package+.
  # Available during +boot.rb+ execution and throughout the application.
  class PackageContext
    # @return [String] The package name (e.g. +"packs/orders"+ or +"."+ for root).
    attr_reader :name

    # @return [String] Absolute path to the package directory.
    attr_reader :root_path

    # @return [PackageContext::Autoloader] Autoloader configuration for this package.
    attr_reader :autoloader

    def initialize(name:, root_path:, config:, autoloader:)
      @name = name
      @root_path = root_path
      @config = config.freeze
      @autoloader = autoloader
    end

    # @return [Boolean] Whether this is the root package.
    def root?
      @name == '.'
    end

    # @return [Hash] Frozen package configuration from +package.yml+.
    def config
      @config
    end

    # Autoload configuration for a package box. Provides {AutoloaderMixin}'s
    # +push_dir+, +collapse+, +ignore+, and +setup+ in +boot.rb+.
    #
    # Registration happens immediately when +push_dir+ or +collapse+ is called,
    # making constants available for the rest of the boot script without an
    # explicit +setup+ call.
    class Autoloader
      include AutoloaderMixin

      def initialize(root_path, box:, default_autoload_dirs: [])
        init_dirs
        @root_path = root_path
        @box = box
        @default_autoload_dirs = default_autoload_dirs
      end

      private

      def do_setup(new_push, new_collapse)
        return unless @box

        all_entries = []

        new_push.each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan(abs_dir))
        end

        new_collapse.each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          root_dir = find_root_for(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir, root_dir: root_dir))
        end

        return if all_entries.empty?

        ZeitwerkScanner.register_autoloads(@box, all_entries)
        file_index = ZeitwerkScanner.build_file_index(all_entries)
        @accumulated_file_index ||= {}
        @accumulated_file_index.merge!(file_index)
      end

      # Returns the absolute root autoload dir that contains abs_dir, or nil.
      def find_root_for(abs_dir)
        (@default_autoload_dirs + @push_dirs)
          .map { |d| File.expand_path(d, @root_path) }
          .find { |root| abs_dir.start_with?("#{root}/") }
      end

      # All user-configured collapse dirs (for BoxManager namespace cleanup).
      def all_collapse_dirs = @collapse_dirs.dup

      # All user-configured ignore dirs (for BoxManager namespace cleanup).
      def ignore_dirs = @ignore_dirs.dup

      # File index accumulated from all auto-setup calls (for BoxManager).
      def accumulated_file_index = @accumulated_file_index || {}

      # Dir info for BoxManager#record_package_dirs (used by info command).
      def dir_info
        {
          autoload: @default_autoload_dirs + @push_dirs,
          collapse: @collapse_dirs.dup,
          ignore: @ignore_dirs.dup,
        }
      end
    end
  end
end
