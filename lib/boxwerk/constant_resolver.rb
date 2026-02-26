# frozen_string_literal: true

module Boxwerk
  # Creates namespace proxy modules for cross-package constant resolution.
  #
  # When package A depends on package B, a proxy module is injected into A's
  # box under B's namespace name. When A accesses B::SomeConstant, the proxy's
  # const_missing fires, resolves the constant from B's box, and caches it
  # via const_set for fast subsequent access.
  #
  # Privacy enforcement: if the dependency has enforce_privacy enabled, only
  # constants in public_constants are accessible. Constants in private_constants
  # are always blocked.
  module ConstantResolver
    # Creates a proxy module that resolves constants from a dependency's box.
    # Constants are loaded lazily and cached after first access.
    def self.create_namespace_proxy(dep_box, file_index: {}, public_constants: nil, private_constants: nil, package_name: nil)
      proxy = Module.new
      pkg_name = package_name

      proxy.define_singleton_method(:const_missing) do |const_name|
        name_str = const_name.to_s

        # Check explicitly private constants
        if private_constants && !private_constants.empty?
          if private_constants.include?(name_str) ||
              private_constants.any? { |pc| name_str.start_with?("#{pc}::") }
            raise NameError, "Privacy violation: '#{name_str}' is private to '#{pkg_name}'"
          end
        end

        # Check public constants whitelist (privacy enforcement)
        if public_constants && !public_constants.include?(name_str)
          raise NameError, "Privacy violation: '#{name_str}' is private to '#{pkg_name}'. " \
            "Only constants in the public path are accessible."
        end

        # Try to get the constant (may already be loaded via autoload or previous require)
        value = begin
          dep_box.const_get(const_name)
        rescue NameError
          # Lazily load the file for this constant
          file = file_index[name_str]
          unless file
            raise NameError, "uninitialized constant #{pkg_name}::#{name_str}"
          end
          dep_box.require(file)
          dep_box.const_get(const_name)
        end

        const_set(const_name, value)
        value
      end

      proxy
    end
  end
end
