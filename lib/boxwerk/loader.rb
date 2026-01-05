# frozen_string_literal: true

module Boxwerk
  # Loader creates isolated Ruby::Box instances for packages and wires imports.
  # Lazily loads exports using Zeitwerk naming conventions and injects constants.
  class Loader
    class << self
      def boot_all(graph, registry)
        order = graph.topological_order

        order.each { |package| boot(package, graph, registry) }
      end

      def boot(package, graph, registry)
        return package if package.booted?

        package.box = Ruby::Box.new
        wire_imports(package.box, package, graph)
        registry.register(package.name, package)

        package
      end

      private

      def load_export(package, const_name)
        # Skip if already loaded (cached)
        return if package.loaded_exports.key?(const_name)

        lib_path = File.join(package.path, 'lib')
        return unless File.directory?(lib_path)

        file_path = find_file_for_constant(lib_path, const_name)
        unless file_path
          raise "Cannot find file for exported constant '#{const_name}' in package '#{package.name}'"
        end

        package.box.require(file_path)
        package.loaded_exports[const_name] = file_path
      end

      def find_file_for_constant(lib_path, const_name)
        if const_name.include?('::')
          nested_path = File.join(lib_path, "#{underscore(const_name)}.rb")
          return nested_path if File.exist?(nested_path)

          parts = const_name.split('::')
          parent_name = parts[0..-2].join('::')
          parent_file = File.join(lib_path, "#{underscore(parent_name)}.rb")
          return parent_file if File.exist?(parent_file)
        else
          conventional_path =
            File.join(lib_path, "#{underscore(const_name)}.rb")
          return conventional_path if File.exist?(conventional_path)
        end

        nil
      end

      def underscore(string)
        string
          .gsub(/::/, '/')
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr('-', '_')
          .downcase
      end

      def wire_imports(box, package, graph)
        package.imports.each do |import_item|
          path, config =
            (
              if import_item.is_a?(String)
                [import_item, nil]
              else
                [import_item.keys.first, import_item.values.first]
              end
            )
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

      def wire_import_strategy(box, package, path, config, dependency)
        case config
        when nil
          create_namespace(package, camelize(File.basename(path)), dependency)
        when String
          create_namespace(package, config, dependency)
        when Array
          config.each do |name|
            set_constant(package, name, get_constant(dependency, name))
          end
        when Hash
          config.each do |remote, local|
            set_constant(package, local, get_constant(dependency, remote))
          end
        end
      end

      def create_namespace(package, namespace_name, dependency)
        if dependency.exports.size == 1
          set_constant(
            package,
            namespace_name,
            get_constant(dependency, dependency.exports.first),
          )
        else
          mod = create_module(package.box, namespace_name)
          dependency.exports.each do |name|
            mod.const_set(name.to_sym, get_constant(dependency, name))
          end
        end
      end

      def get_constant(package, name)
        load_export(package, name)
        package.box.const_get(name.to_sym)
      end

      def set_constant(package, name, value)
        package.box.const_set(name.to_sym, value)
      end

      def create_module(box, name)
        if box.const_defined?(name.to_sym, false)
          return box.const_get(name.to_sym)
        end

        mod = Module.new
        box.const_set(name.to_sym, mod)
        mod
      end

      def camelize(string)
        string.split('_').map(&:capitalize).join
      end
    end
  end
end
