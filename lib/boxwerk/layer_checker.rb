# frozen_string_literal: true

require 'yaml'

module Boxwerk
  # Enforces packwerk-extensions layer rules.
  # Layers defined in packwerk.yml (ordered highest to lowest).
  # Packages can only depend on same or lower layers.
  module LayerChecker
    class << self
      # Reads layer definitions from packwerk.yml.
      # Returns array ordered highest to lowest, or empty if not configured.
      def layers_for(root_path)
        config_path = File.join(root_path, 'packwerk.yml')
        return [] unless File.exist?(config_path)

        config = YAML.safe_load_file(config_path) || {}
        config['layers'] || config['architecture_layers'] || []
      end

      def enforces_layers?(package)
        setting = package.config['enforce_layers'] || package.config['enforce_architecture']
        [true, 'strict'].include?(setting)
      end

      def layer_for(package)
        package.config['layer']
      end

      # Returns the index of a layer (lower index = higher layer).
      def layer_index(layer_name, layers)
        layers.index(layer_name)
      end

      # Validates that a dependency doesn't violate layer ordering.
      # A package can only depend on packages in the same or lower layer.
      # Returns nil if OK, or an error message string if violated.
      def validate_dependency(from_package, to_package, layers)
        return nil unless enforces_layers?(from_package)
        return nil if layers.empty?

        from_layer = layer_for(from_package)
        to_layer = layer_for(to_package)

        # If either package has no layer assigned, allow
        return nil unless from_layer && to_layer

        from_idx = layer_index(from_layer, layers)
        to_idx = layer_index(to_layer, layers)

        # If layers aren't in the defined list, allow
        return nil unless from_idx && to_idx

        # Lower index = higher layer. Can only depend on same or higher index (lower layer).
        if to_idx < from_idx
          "'#{from_package.name}' (layer: #{from_layer}) cannot depend on " \
            "'#{to_package.name}' (layer: #{to_layer}) — higher layer"
        end
      end
    end
  end
end
