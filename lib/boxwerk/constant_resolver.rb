# frozen_string_literal: true

module Boxwerk
  # Resolves constants from dependency packages without namespace wrapping.
  #
  # When package A depends on package B, B's constants are accessible
  # directly in A (e.g. Invoice, not Finance::Invoice). A const_missing
  # handler searches all direct dependencies in order and resolves the
  # first match. Privacy enforcement is applied per-dependency.
  module ConstantResolver
    # Installs a const_missing handler on the box that searches all
    # dependency boxes for the requested constant. Each dependency entry
    # contains: :box, :file_index, :public_constants, :private_constants,
    # :package_name.
    def self.install_dependency_resolver(box, deps_config)
      resolver = build_resolver(deps_config)
      box.const_set(:BOXWERK_DEPENDENCY_RESOLVER, resolver)

      # Define const_missing on Object within the box so that top-level
      # constant lookups (e.g. Invoice) trigger the dependency search.
      box.eval(<<~RUBY)
        class Object
          def self.const_missing(const_name)
            BOXWERK_DEPENDENCY_RESOLVER.call(const_name)
          end
        end
      RUBY
    end

    # Builds a resolver proc that searches dependencies for a constant.
    def self.build_resolver(deps_config)
      proc do |const_name|
        name_str = const_name.to_s
        found = false
        value = nil

        deps_config.each do |dep|
          dep_box = dep[:box]
          file_index = dep[:file_index]
          public_constants = dep[:public_constants]
          private_constants = dep[:private_constants]
          pkg_name = dep[:package_name]

          # Check if this dependency has the constant or a namespace
          # matching it (e.g. "Menu" when file_index has "Menu::Item")
          has_constant =
            file_index.key?(name_str) ||
              file_index.any? { |k, _| k.start_with?("#{name_str}::") } ||
              (
                begin
                  dep_box.const_get(const_name)
                  true
                rescue NameError
                  false
                end
              )

          next unless has_constant

          # Check explicitly private constants
          if private_constants && !private_constants.empty?
            if private_constants.include?(name_str) ||
                 private_constants.any? { |pc| name_str.start_with?("#{pc}::") }
              raise NameError,
                    "Privacy violation: '#{name_str}' is private to '#{pkg_name}'"
            end
          end

          # Check public constants whitelist (privacy enforcement).
          # A namespace module (e.g. Menu) is allowed if any public
          # constant lives under it (e.g. Menu::Item).
          if public_constants
            direct_match = public_constants.include?(name_str)
            namespace_match =
              public_constants.any? { |pc| pc.start_with?("#{name_str}::") }
            unless direct_match || namespace_match
              raise NameError,
                    "Privacy violation: '#{name_str}' is private to '#{pkg_name}'. " \
                      'Only constants in the public path are accessible.'
            end
          end

          # Resolve the constant from the dependency box
          value =
            begin
              dep_box.const_get(const_name)
            rescue NameError
              file = file_index[name_str]
              if file
                dep_box.require(file)
                dep_box.const_get(const_name)
              else
                # Namespace module — trigger autoload of a child constant
                # so the module gets defined in the dependency box.
                child_key =
                  file_index.keys.find { |k| k.start_with?("#{name_str}::") }
                if child_key
                  child_file = file_index[child_key]
                  dep_box.require(child_file)
                  dep_box.const_get(const_name)
                else
                  raise NameError, "uninitialized constant #{name_str}"
                end
              end
            end

          found = true
          break
        end

        raise NameError, "uninitialized constant #{name_str}" unless found

        value
      end
    end
  end
end
