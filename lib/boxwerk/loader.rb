# frozen_string_literal: true

module Boxwerk
  # Loader handles the creation and initialization of isolated package boxes
  class Loader
    class << self
      # Boot all packages in topological order
      # @param graph [Boxwerk::Graph] The dependency graph
      # @param registry [Boxwerk::Registry] The registry instance
      def boot_all(graph, registry)
        order = graph.topological_order

        order.each { |package| boot(package, graph, registry) }
      end

      # Boot a single package
      # @param package [Boxwerk::Package] The package to boot
      # @param graph [Boxwerk::Graph] The dependency graph
      # @param registry [Boxwerk::Registry] The registry instance
      def boot(package, graph, registry)
        return package if package.booted?

        # Check if RUBY_BOX environment variable is set
        unless ENV['RUBY_BOX'] == '1'
          raise 'Boxwerk requires RUBY_BOX=1 environment variable to enable Ruby::Box support'
        end

        # Check if we have Ruby::Box support
        unless defined?(Ruby::Box)
          raise 'Boxwerk requires Ruby 4.0+ with Ruby::Box support'
        end

        # All packages (including root) get their own isolated boxes
        box = Ruby::Box.new

        # Store the box reference first so it's available during wiring
        package.box = box

        # Wire imports based on configuration (exports loaded lazily on-demand)
        wire_imports(box, package, graph)

        # Register in the registry
        registry.register(package.name, package)

        package
      end

      private

      # Load a specific exported constant from package's lib directory using Zeitwerk conventions
      # This enforces strict isolation - only requested exports are loaded, lazily
      # @param package [Boxwerk::Package] The package
      # @param const_name [String] The constant name to load
      def load_export(package, const_name)
        # Skip if already loaded (cached)
        return if package.loaded_exports.key?(const_name)

        lib_path = File.join(package.path, 'lib')
        return unless File.directory?(lib_path)

        # Find the file path for this constant using Zeitwerk conventions
        file_path = find_file_for_constant(lib_path, const_name)

        unless file_path
          raise "Cannot find file for exported constant '#{const_name}' in package '#{package.name}' at #{lib_path}"
        end

        # Load the file in the package's box
        package.box.require(file_path)

        # Cache the mapping AFTER successful load
        package.loaded_exports[const_name] = file_path
      end

      # Load only exported constants from package's lib directory using Zeitwerk conventions
      # @param box [Ruby::Box] The box instance
      # @param package [Boxwerk::Package] The package
      def load_exports(box, package)
        lib_path = File.join(package.path, 'lib')
        return unless File.directory?(lib_path)

        # Find all files that might contain exported constants and map them to constants
        files_to_load = {}  # file_path => [const_name, ...]

        package.exports.each do |const_name|
          # Skip if already loaded (cached)
          next if package.loaded_exports.key?(const_name)

          # Find the file path for this constant using Zeitwerk conventions
          file_path = find_file_for_constant(lib_path, const_name)

          unless file_path
            raise "Cannot find file for exported constant '#{const_name}' in package '#{package.name}' at #{lib_path}"
          end

          files_to_load[file_path] ||= []
          files_to_load[file_path] << const_name
        end

        # Load only the discovered files in the box (strict mode - no fallback)
        files_to_load.keys.sort.each do |file|
          box.require(file)

          # Cache the mapping AFTER successful load
          files_to_load[file].each do |const_name|
            package.loaded_exports[const_name] = file
          end
        end
      end

      # Find the file that should define a constant using Zeitwerk's conventions
      # Handles nested constants: Foo::Bar can be in lib/foo/bar.rb OR lib/foo.rb
      # @param lib_path [String] The lib directory path
      # @param const_name [String] The constant name (can include ::)
      # @return [String, nil] The file path or nil if not found
      def find_file_for_constant(lib_path, const_name)
        # For nested constants like Foo::Bar, try the nested path first
        if const_name.include?('::')
          # Try conventional nested path: Foo::Bar -> lib/foo/bar.rb
          nested_path = File.join(lib_path, "#{underscore(const_name)}.rb")
          return nested_path if File.exist?(nested_path)

          # Fall back to parent path: Foo::Bar -> lib/foo.rb
          # The parent file might define the nested constant
          parts = const_name.split('::')
          parent_name = parts[0..-2].join('::')
          parent_file = if parent_name.empty?
            # Top-level nested constant (shouldn't happen, but handle it)
            File.join(lib_path, "#{underscore(parts[-1])}.rb")
          else
            File.join(lib_path, "#{underscore(parent_name)}.rb")
          end
          return parent_file if File.exist?(parent_file)
        else
          # For top-level constants, try conventional path
          conventional_path = File.join(lib_path, "#{underscore(const_name)}.rb")
          return conventional_path if File.exist?(conventional_path)
        end

        nil
      end

      # Convert CamelCase to snake_case (Zeitwerk-compatible)
      # @param string [String] The string to convert
      # @return [String] The underscored string
      def underscore(string)
        string
          .gsub(/::/, '/')
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr('-', '_')
          .downcase
      end

      # Wire imports according to YAML configuration (list format)
      # @param box [Ruby::Box] The box instance
      # @param package [Boxwerk::Package] The package being booted
      # @param graph [Boxwerk::Graph] The dependency graph
      def wire_imports(box, package, graph)
        package.imports.each do |import_item|
          # Normalize: String or Hash
          if import_item.is_a?(String)
            path = import_item
            config = nil
          else
            path = import_item.keys.first
            config = import_item.values.first
          end

          dep_name = File.basename(path)
          dependency = graph.packages[dep_name]

          unless dependency
            raise "Cannot resolve dependency '#{path}' for package '#{package.name}'"
          end

          unless dependency.booted?
            raise "Dependency '#{dep_name}' not booted yet"
          end

          wire_import_strategy(box, package, path, config, dependency)
        end
      end

      # Execute the appropriate wiring strategy based on config type
      # @param box [Ruby::Box] The box instance
      # @param package [Boxwerk::Package] The current package being wired
      # @param path [String] The dependency path
      # @param config [nil, String, Array, Hash] The import configuration
      # @param dependency [Boxwerk::Package] The dependency package
      def wire_import_strategy(box, package, path, config, dependency)
        case config
        when nil
          # Strategy 1: Default Namespace ("packages/billing" -> "Billing")
          name = camelize(File.basename(path))
          create_namespace(package, name, dependency)
        when String
          # Strategy 2: Aliased Namespace ("packages/identity": "Auth")
          create_namespace(package, config, dependency)
        when Array
          # Strategy 3: Selective List (["Log", "Metrics"])
          config.each do |const_name|
            value = get_constant(dependency, const_name)
            set_constant(package, const_name, value)
          end
        when Hash
          # Strategy 4: Selective Rename ({Invoice: "Bill"})
          config.each do |remote_name, local_alias|
            value = get_constant(dependency, remote_name)
            set_constant(package, local_alias, value)
          end
        end
      end

      # Create a namespace module and populate with all exports
      # Or import directly if single export (optimization)
      # @param package [Boxwerk::Package] The current package
      # @param namespace_name [String] The module name to create
      # @param dependency [Boxwerk::Package] The dependency package
      def create_namespace(package, namespace_name, dependency)
        if dependency.exports.size == 1
          # Single export optimization: import directly
          value = get_constant(dependency, dependency.exports.first)
          set_constant(package, namespace_name, value)
        else
          # Multiple exports: create namespace module
          mod = create_module(package.box, namespace_name)
          dependency.exports.each do |export_name|
            value = get_constant(dependency, export_name)
            mod.const_set(export_name.to_sym, value)
          end
        end
      end

      # Get a constant from a package's box, loading it lazily if needed
      # @param package [Boxwerk::Package] The package to get the constant from
      # @param name [String] The constant name
      # @return [Object] The constant value
      def get_constant(package, name)
        # Load the export lazily
        load_export(package, name)

        package.box.const_get(name.to_sym)
      end

      # Set a constant in a package's box
      # @param package [Boxwerk::Package] The package to set the constant in
      # @param name [String] The constant name
      # @param value [Object] The constant value
      def set_constant(package, name, value)
        package.box.const_set(name.to_sym, value)
      end

      # Create a module in the box
      def create_module(box, name)
        unless box.const_defined?(name.to_sym, false)
          mod = Module.new
          box.const_set(name.to_sym, mod)
          mod
        else
          box.const_get(name.to_sym)
        end
      end

      # Set a constant within a module in the box
      def set_const_in_module(box, module_name, const_name, value)
        mod = box.const_get(module_name.to_sym, false)
        mod.const_set(const_name.to_sym, value)
      end

      # Simple camelization (underscore to CamelCase)
      def camelize(string)
        string.split('_').map(&:capitalize).join
      end
    end
  end
end
