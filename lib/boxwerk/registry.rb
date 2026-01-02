# frozen_string_literal: true

module Boxwerk
  # Registry for tracking booted package instances
  # This allows packages to be booted once and reused
  class Registry
    def initialize
      @registry = {}
    end

    # Register a booted package
    # @param name [Symbol] Package name
    # @param instance [Object] The booted package instance
    def register(name, instance)
      @registry[name] = instance
    end

    # Retrieve a booted package
    # @param name [Symbol] Package name
    # @return [Object, nil] The package instance or nil
    def get(name)
      @registry[name]
    end

    # Check if a package is registered
    # @param name [Symbol] Package name
    # @return [Boolean]
    def registered?(name)
      @registry.key?(name)
    end

    # Clear the registry (useful for testing)
    def clear!
      @registry = {}
    end
  end
end
