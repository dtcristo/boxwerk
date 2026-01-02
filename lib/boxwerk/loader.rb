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

        # 1. Load implementation files (skip for root package - no lib to load)
        load_implementation(box, package) unless package == graph.root

        # 2. Wire imports based on configuration
        wire_imports(box, package, graph)

        # 3. Store the box reference
        package.box = box

        # 4. Register in the registry
        registry.register(package.name, package)

        package
      end

      private

      # Load all Ruby files from package's lib directory
      # @param box [Ruby::Box] The box instance
      # @param package [Boxwerk::Package] The package
      def load_implementation(box, package)
        lib_path = File.join(package.path, 'lib')
        return unless File.directory?(lib_path)

        Dir
          .glob(File.join(lib_path, '**', '*.rb'))
          .sort
          .each { |file| box.require(file) }
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

          wire_import_strategy(box, path, config, dependency)
        end
      end

      # Execute the appropriate wiring strategy based on config type
      # @param box [Ruby::Box] The box instance
      # @param path [String] The dependency path
      # @param config [nil, String, Array, Hash] The import configuration
      # @param dependency [Boxwerk::Package] The dependency package
      def wire_import_strategy(box, path, config, dependency)
        case config
        when nil
          # Strategy 1: Default Namespace ("packages/billing" -> "Billing")
          name = camelize(File.basename(path))
          create_namespace(box, name, dependency)
        when String
          # Strategy 2: Aliased Namespace ("packages/identity": "Auth")
          create_namespace(box, config, dependency)
        when Array
          # Strategy 3: Selective List (["Log", "Metrics"])
          config.each do |const_name|
            val = get_const(dependency.box, const_name)
            set_const(box, const_name, val)
          end
        when Hash
          # Strategy 4: Selective Rename ({Invoice: "Bill"})
          config.each do |remote_name, local_alias|
            val = get_const(dependency.box, remote_name)
            set_const(box, local_alias, val)
          end
        end
      end

      # Create a namespace module and populate with all exports
      # Or import directly if single export (optimization)
      # @param box [Ruby::Box] The box instance
      # @param namespace_name [String] The module name to create
      # @param dependency [Boxwerk::Package] The dependency package
      def create_namespace(box, namespace_name, dependency)
        if dependency.exports.size == 1
          # Single export optimization: import directly
          const_value = get_const(dependency.box, dependency.exports.first)
          set_const(box, namespace_name, const_value)
        else
          # Multiple exports: create namespace module
          create_module(box, namespace_name)
          dependency.exports.each do |export_name|
            const_value = get_const(dependency.box, export_name)
            set_const_in_module(box, namespace_name, export_name, const_value)
          end
        end
      end

      # Get a constant from a box
      def get_const(box, name)
        box.const_get(name.to_sym)
      end

      # Set a constant in the box
      def set_const(box, name, value)
        box.const_set(name.to_sym, value)
      end

      # Create a module in the box
      def create_module(box, name)
        unless box.const_defined?(name.to_sym)
          box.const_set(name.to_sym, Module.new)
        end
      end

      # Set a constant within a module in the box
      def set_const_in_module(box, module_name, const_name, value)
        mod = box.const_get(module_name.to_sym)
        mod.const_set(const_name.to_sym, value)
      end

      # Simple camelization (underscore to CamelCase)
      def camelize(string)
        string.split('_').map(&:capitalize).join
      end
    end
  end
end
