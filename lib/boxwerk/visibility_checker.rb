# frozen_string_literal: true

module Boxwerk
  # VisibilityChecker enforces packwerk-extensions visibility rules.
  # A package with `enforce_visibility: true` and `visible_to` list
  # is only accessible to the listed packages.
  module VisibilityChecker
    class << self
      def enforces_visibility?(package)
        package.config['enforce_visibility'] == true
      end

      # Returns the list of package names that can see this package.
      def visible_to(package)
        package.config['visible_to'] || []
      end

      # Returns true if `accessor_package` is allowed to see `target_package`.
      def visible?(target_package, accessor_package)
        return true unless enforces_visibility?(target_package)

        allowed = visible_to(target_package)
        allowed.include?(accessor_package.name)
      end
    end
  end
end
