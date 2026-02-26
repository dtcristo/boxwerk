# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  # Shared helpers for integration tests that create packages in a tmpdir
  # and boot the system with real Ruby::Box isolation.
  module IntegrationTestHelper
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset!
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset!
    end

    private

    def create_package_dir(name)
      dir = File.join(@tmpdir, 'packages', name)
      FileUtils.mkdir_p(File.join(dir, 'lib'))
      dir
    end

    def create_package(path, dependencies: nil, enforce_privacy: nil, private_constants: nil,
                       enforce_visibility: nil, visible_to: nil,
                       enforce_folder_privacy: nil,
                       enforce_layers: nil, layer: nil)
      content = { 'enforce_dependencies' => true }
      content['dependencies'] = dependencies if dependencies
      content['enforce_privacy'] = enforce_privacy unless enforce_privacy.nil?
      content['private_constants'] = private_constants if private_constants
      content['enforce_visibility'] = enforce_visibility unless enforce_visibility.nil?
      content['visible_to'] = visible_to if visible_to
      content['enforce_folder_privacy'] = enforce_folder_privacy unless enforce_folder_privacy.nil?
      content['enforce_layers'] = enforce_layers unless enforce_layers.nil?
      content['layer'] = layer if layer

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end

    def boot_system
      resolver = PackageResolver.new(@tmpdir)
      box_manager = BoxManager.new(@tmpdir)
      box_manager.boot_all(resolver)

      { resolver: resolver, box_manager: box_manager }
    end
  end
end
