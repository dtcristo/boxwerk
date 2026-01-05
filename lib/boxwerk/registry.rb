# frozen_string_literal: true

module Boxwerk
  # Registry tracks booted package instances to ensure each package boots only once.
  class Registry
    def initialize
      @registry = {}
    end

    def register(name, instance)
      @registry[name] = instance
    end

    def get(name)
      @registry[name]
    end

    def registered?(name)
      @registry.key?(name)
    end

    def clear!
      @registry = {}
    end
  end
end
