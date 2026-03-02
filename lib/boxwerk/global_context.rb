# frozen_string_literal: true

module Boxwerk
  # Runtime context for the root box, accessible via +Boxwerk.global+ from
  # any box context (global boot, package boot, or application code).
  class GlobalContext
    # @return [GlobalContext::Autoloader] Autoloader configuration for the root box.
    attr_reader :autoloader

    def initialize(root_path)
      @root_path = root_path
      @autoloader = Autoloader.new(root_path)
      @default_dirs = []
    end

    # Autoload configuration for the root box. Provides {AutoloaderMixin}'s
    # +push_dir+, +collapse+, +ignore+, and +setup+ in +global/boot.rb+.
    #
    # Registrations are lazy (autoload entries only) until the framework
    # eager-loads them after +global/boot.rb+ completes.
    class Autoloader
      include AutoloaderMixin

      def initialize(root_path)
        init_dirs
        @root_path = root_path
        @accumulated_entries = []
      end

      private

      def do_setup(new_push, new_collapse)
        all_entries = []

        new_push.each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan(abs_dir))
        end

        new_collapse.each do |dir|
          abs_dir = File.expand_path(dir, @root_path)
          next unless File.directory?(abs_dir)
          all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir))
        end

        return if all_entries.empty?

        ZeitwerkScanner.register_autoloads(Ruby::Box.root, all_entries)
        @accumulated_entries.concat(all_entries)
      end

      # Eagerly requires all registered files so child boxes inherit constants.
      # Called by Setup after global/boot.rb when eager_load_global is true.
      def eager_load!
        return if @accumulated_entries.empty?

        root_box = Ruby::Box.root
        @accumulated_entries.each { |e| root_box.require(e.file) if e.file }
      end

      # Dir info for the info command (accessed via GlobalContext#dir_info).
      def dir_info
        { autoload: @push_dirs.dup, collapse: @collapse_dirs.dup, ignore: @ignore_dirs.dup }
      end
    end

    private

    # Records a directory scanned by Setup (e.g. global/) for the info command.
    def record_scanned_dir(rel_path)
      @default_dirs << rel_path
    end

    # Returns combined dir info for the info command.
    def dir_info
      al_info = @autoloader.__send__(:dir_info)
      {
        autoload: @default_dirs + al_info[:autoload],
        collapse: al_info[:collapse],
        ignore: al_info[:ignore],
      }
    end
  end
end
