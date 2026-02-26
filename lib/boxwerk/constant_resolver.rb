# frozen_string_literal: true

module Boxwerk
  # ConstantResolver creates namespace proxy modules that lazily resolve
  # constants from dependency packages via const_missing. Only direct
  # dependencies are wired, preventing transitive leakage.
  # Optionally enforces privacy (packwerk-extensions compatibility).
  module ConstantResolver
    # Creates a namespace proxy module that lazily resolves constants
    # from a dependency's Ruby::Box via const_missing.
    #
    # @param dep_box [Ruby::Box] the dependency's box
    # @param public_constants [Set, nil] if non-nil, only these constants are accessible
    # @param private_constants [Set] constants explicitly marked private
    # @param package_name [String] name of the dependency package (for error messages)
    def self.create_namespace_proxy(dep_box, public_constants: nil, private_constants: nil, package_name: nil)
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

        value = dep_box.const_get(const_name)
        const_set(const_name, value)
        value
      end

      proxy
    end
  end
end
