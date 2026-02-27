# frozen_string_literal: true

require 'zeitwerk'

module Boxwerk
  # Uses Zeitwerk's file system scanner and inflector to discover constants
  # in a directory. Zeitwerk's autoload registration cannot be used directly
  # inside Ruby::Box (autoloads register in the box where the code was
  # defined, not where it's called), so we only use Zeitwerk for:
  #
  #   - File discovery (respecting Zeitwerk conventions: hidden dirs, etc.)
  #   - Inflection (file names → constant names)
  #
  # The actual autoload registration is done by BoxManager using box.eval.
  module ZeitwerkScanner
    Entry = Data.define(:type, :cname, :full_path, :file, :parent, :dir)

    # Scans a directory and returns an array of Entry structs describing
    # the constants and namespaces found. Uses a temporary Zeitwerk::Loader
    # for its FileSystem scanner and Inflector.
    def self.scan(dir)
      loader = Zeitwerk::Loader.new
      loader.push_dir(dir)
      inflector = loader.inflector
      fs = Zeitwerk::Loader::FileSystem.new(loader)

      entries = []
      scan_dir(fs, inflector, dir, "", entries)
      entries
    end

    # Registers autoloads in a Ruby::Box based on scan results.
    # Implicit namespaces become Module.new, explicit namespaces are
    # eagerly loaded so child autoloads can attach to them.
    def self.register_autoloads(box, entries)
      namespaces = entries.select { |e| e.type == :namespace }
      files = entries.select { |e| e.type == :file }

      # Phase 1: Set up namespaces
      namespaces.each do |ns|
        if ns.file
          # Explicit namespace: autoload the .rb file
          register_autoload(box, ns.parent, ns.cname, ns.file)
        else
          # Implicit namespace: create empty module
          define_implicit_module(box, ns.parent, ns.cname, ns.full_path)
        end
      end

      # Phase 2: Eagerly trigger explicit namespaces so children can attach
      namespaces.each do |ns|
        box.eval(ns.full_path) if ns.file
      end

      # Phase 3: Register file autoloads
      files.each do |f|
        register_autoload(box, f.parent, f.cname, f.file)
      end
    end

    # Builds a file index (const_name → file_path) from scan entries.
    # Used by ConstantResolver for dependency wiring.
    def self.build_file_index(entries)
      index = {}
      entries.each do |e|
        index[e.full_path] = e.file if e.file
      end
      index
    end

    class << self
      private

      def scan_dir(fs, inflector, dir, parent_path, entries)
        fs.ls(dir) do |basename, abspath, ftype|
          if ftype == :file
            cname = inflector.camelize(basename.delete_suffix(".rb"), dir)
            full_path = parent_path.empty? ? cname : "#{parent_path}::#{cname}"
            entries << Entry.new(
              type: :file, cname: cname, full_path: full_path,
              file: abspath, parent: parent_path, dir: nil
            )
          elsif ftype == :directory
            cname = inflector.camelize(basename, dir)
            full_path = parent_path.empty? ? cname : "#{parent_path}::#{cname}"
            rb_file = "#{abspath}.rb"
            has_rb = File.exist?(rb_file)
            entries << Entry.new(
              type: :namespace, cname: cname, full_path: full_path,
              file: has_rb ? rb_file : nil, parent: parent_path, dir: abspath
            )
            scan_dir(fs, inflector, abspath, full_path, entries)
          end
        end
      end

      def register_autoload(box, parent, cname, file)
        if parent.empty?
          box.eval("autoload :#{cname}, #{file.inspect}")
        else
          box.eval("#{parent}.autoload(:#{cname}, #{file.inspect})")
        end
      end

      def define_implicit_module(box, parent, cname, full_path)
        if parent.empty?
          box.eval("#{cname} = Module.new unless defined?(#{cname})")
        else
          box.eval("#{parent}.const_set(:#{cname}, Module.new) unless defined?(#{full_path})")
        end
      end
    end
  end
end
