# frozen_string_literal: true

module Boxwerk
  # Enforces packwerk-extensions folder_privacy rules.
  # When enabled, only sibling packs and parent packs can access this package.
  module FolderPrivacyChecker
    class << self
      def enforces_folder_privacy?(package)
        package.config['enforce_folder_privacy'] == true
      end

      # Returns true if `accessor_package` is allowed to access `target_package`.
      # Allowed: parent packs and sibling packs (same parent directory).
      def accessible?(target_package, accessor_package)
        return true unless enforces_folder_privacy?(target_package)

        target_path = target_package.name
        accessor_path = accessor_package.name

        # Root package can always access anything
        return true if accessor_package.root?

        target_parent = File.dirname(target_path)
        accessor_parent = File.dirname(accessor_path)

        # Parent pack: accessor is a prefix of target's parent
        return true if target_path.start_with?("#{accessor_path}/")

        # Grandparent and above: accessor's parent is a prefix of target's parent
        return true if target_parent.start_with?("#{accessor_parent}/") && accessor_parent != '.'

        # Sibling: same parent directory
        return true if target_parent == accessor_parent

        # Parent of parent (ancestor)
        return true if accessor_path == target_parent || target_parent.start_with?("#{accessor_path}/")

        false
      end
    end
  end
end
