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
    #
    # +all_packages_ref+ is an optional hash with lazy references to
    # :file_indexes, :packages, :root_path, :dep_names, and :self_name
    # for producing helpful NameError hints.
    # +package_name+ is the name of the current package (for error messages).
    def self.install_dependency_resolver(
      box,
      deps_config,
      all_packages_ref: nil,
      package_name: nil
    )
      resolver =
        build_resolver(
          deps_config,
          all_packages_ref: all_packages_ref,
          package_name: package_name,
        )
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
    def self.build_resolver(
      deps_config,
      all_packages_ref: nil,
      package_name: nil
    )
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
              from = package_name ? " referenced from '#{package_name}'" : ''
              raise NameError.new(
                "private constant #{name_str}#{from} — #{name_str} is private to '#{pkg_name}'",
                const_name,
              )
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
              from = package_name ? " referenced from '#{package_name}'" : ''
              raise NameError.new(
                "private constant #{name_str}#{from} — #{name_str} is private to '#{pkg_name}'",
                const_name,
              )
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
                  raise NameError.new(
                    "uninitialized constant #{name_str}",
                    const_name,
                  )
                end
              end
            end

          found = true
          break
        end

        unless found
          hint = find_hint(name_str, all_packages_ref)
          msg =
            if hint
              visibility = hint[:private] ? 'private in' : 'defined in'
              from = package_name ? ", not a dependency of '#{package_name}'" : ''
              "uninitialized constant #{name_str} (#{visibility} '#{hint[:package_name]}'#{from})"
            else
              "uninitialized constant #{name_str}"
            end
          raise NameError.new(msg, const_name)
        end

        value
      end
    end

    # Searches all packages (via lazy ref) for one whose file_index
    # contains the given constant name. Returns a hash with :package_name
    # and :private (boolean), or nil if not found.
    def self.find_hint(name_str, all_packages_ref)
      return nil unless all_packages_ref

      file_indexes = all_packages_ref[:file_indexes]
      packages = all_packages_ref[:packages]
      root_path = all_packages_ref[:root_path]
      dep_names = all_packages_ref[:dep_names]
      self_name = all_packages_ref[:self_name]

      packages.each_value do |pkg|
        next if pkg.name == self_name
        next if dep_names.include?(pkg.name)

        pkg_file_index = file_indexes[pkg.name] || {}
        next unless pkg_file_index.key?(name_str) ||
          pkg_file_index.any? { |k, _| k.start_with?("#{name_str}::") }

        pub_consts = PrivacyChecker.public_constants(pkg, root_path)
        is_private =
          if pub_consts
            !pub_consts.include?(name_str) &&
              !pub_consts.any? { |pc| pc.start_with?("#{name_str}::") }
          else
            false
          end

        return { package_name: pkg.name, private: is_private }
      end
      nil
    end
  end
end
