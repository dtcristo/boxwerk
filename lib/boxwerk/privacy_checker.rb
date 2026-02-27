# frozen_string_literal: true

require 'zeitwerk'

module Boxwerk
  # Enforces privacy rules at runtime.
  # Reads enforce_privacy, public_path, and private_constants from package.yml.
  # Files with `# pack_public: true` sigil are treated as public.
  module PrivacyChecker
    DEFAULT_PUBLIC_PATH = 'public/'
    PUBLICIZED_SIGIL_REGEX = /#.*pack_public:\s*true/

    class << self
      # Returns true if the package enforces privacy.
      def enforces_privacy?(package)
        setting = package.config['enforce_privacy']
        [true, 'strict'].include?(setting)
      end

      # Returns the public path for a package (absolute).
      def public_path_for(package, root_path)
        user_path = package.config['public_path']
        relative =
          if user_path
            user_path.end_with?('/') ? user_path : "#{user_path}/"
          else
            DEFAULT_PUBLIC_PATH
          end

        if package.root?
          File.join(root_path, relative)
        else
          File.join(root_path, package.name, relative)
        end
      end

      # Returns the set of public constant names for a package.
      # These are derived from files in the public_path using Ruby naming conventions.
      def public_constants(package, root_path)
        return nil unless enforces_privacy?(package)

        pub_path = public_path_for(package, root_path)
        constants = Set.new

        if File.directory?(pub_path)
          Dir
            .glob(File.join(pub_path, '**', '*.rb'))
            .each do |file|
              const_name = constant_name_from_path(file, pub_path)
              constants.add(const_name) if const_name
            end
        end

        # Also scan all package files for pack_public: true sigil
        package_lib = package_lib_path(package, root_path)
        if package_lib && File.directory?(package_lib)
          Dir
            .glob(File.join(package_lib, '**', '*.rb'))
            .each do |file|
              if publicized_file?(file)
                const_name = constant_name_from_path(file, package_lib)
                constants.add(const_name) if const_name
              end
            end
        end

        constants
      end

      # Returns the set of explicitly private constant names.
      # Strips leading :: prefix.
      def private_constants_list(package)
        (package.config['private_constants'] || [])
          .map { |name| name.start_with?('::') ? name[2..] : name }
          .to_set
      end

      # Checks if a constant is accessible from outside the package.
      # Returns true if accessible, false if blocked by privacy.
      def accessible?(
        const_name,
        package,
        root_path,
        public_constants_cache: nil
      )
        return true unless enforces_privacy?(package)

        # Check explicitly private constants
        privates = private_constants_list(package)
        return false if privates.include?(const_name.to_s)
        if privates.any? { |pc| const_name.to_s.start_with?("#{pc}::") }
          return false
        end

        # Check if constant is in the public set
        pub_consts =
          public_constants_cache || public_constants(package, root_path)
        return true if pub_consts.nil? # privacy not enforced

        # If public_path has files, check against them
        # If public_path is empty/doesn't exist but enforce_privacy is on,
        # all constants are private (no public API defined)
        pub_consts.include?(const_name.to_s)
      end

      private

      # Derives a constant name from a file path relative to a base directory.
      # Uses Zeitwerk's inflector for Ruby naming conventions.
      def constant_name_from_path(file_path, base_path)
        normalized_base = base_path.end_with?('/') ? base_path : "#{base_path}/"
        relative = file_path.delete_prefix(normalized_base).delete_suffix('.rb')
        return nil if relative.empty?

        inflector = Zeitwerk::Inflector.new
        relative
          .split('/')
          .map { |part| inflector.camelize(part, base_path) }
          .join('::')
      end

      # Checks if a file contains the pack_public: true sigil in first 5 lines.
      def publicized_file?(file_path)
        File
          .foreach(file_path)
          .first(5)
          .any? { |line| line.match?(PUBLICIZED_SIGIL_REGEX) }
      rescue Errno::ENOENT
        false
      end

      def package_lib_path(package, root_path)
        if package.root?
          nil
        else
          File.join(root_path, package.name, 'lib')
        end
      end
    end
  end
end
