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
    class Autoloader
      attr_reader :autoload_dirs, :collapse_dirs, :ignore_dirs

      def initialize(root_path)
        @root_path = root_path
        @autoload_dirs = []
        @collapse_dirs = []
        @ignore_dirs = []
      end

      def push_dir(dir)
        @autoload_dirs << dir
      end

      def collapse(dir)
        @collapse_dirs << dir
      end

      def ignore(dir)
        @ignore_dirs << dir
      end
    end
  end
end
