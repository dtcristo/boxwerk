# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for layer enforcement: same layer OK, lower layer OK,
  # higher layer raises LayerViolationError.
  class LayerIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_layer_allows_same_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_layers: true, layer: 'core')
      File.write(
        File.join(a_dir, 'lib', 'class_a.rb'),
        "class ClassA\n  def self.value\n    'core'\n  end\nend\n",
      )

      b_dir = create_package_dir('b')
      create_package(b_dir, enforce_layers: true, layer: 'core', dependencies: ['packs/a'])
      File.write(File.join(b_dir, 'lib', 'class_b.rb'), "class ClassB\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      b_box = result[:box_manager].boxes['packs/b']
      assert_equal 'core', b_box.eval('A::ClassA.value')
    end

    def test_layer_allows_lower_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      util_dir = create_package_dir('util')
      create_package(util_dir, layer: 'utility')
      File.write(
        File.join(util_dir, 'lib', 'util_class.rb'),
        "class UtilClass\n  def self.value\n    'util'\n  end\nend\n",
      )

      feature_dir = create_package_dir('feature')
      create_package(feature_dir, enforce_layers: true, layer: 'feature', dependencies: ['packs/util'])
      File.write(File.join(feature_dir, 'lib', 'feature_class.rb'), "class FeatureClass\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/util packs/feature])

      result = boot_system

      feature_box = result[:box_manager].boxes['packs/feature']
      assert_equal 'util', feature_box.eval('Util::UtilClass.value')
    end

    def test_layer_blocks_higher_layer_dependency
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump('layers' => %w[feature core utility]))

      feature_dir = create_package_dir('feature')
      create_package(feature_dir, layer: 'feature')
      File.write(File.join(feature_dir, 'lib', 'feature_class.rb'), "class FeatureClass\nend\n")

      util_dir = create_package_dir('util')
      create_package(util_dir, enforce_layers: true, layer: 'utility', dependencies: ['packs/feature'])
      File.write(File.join(util_dir, 'lib', 'util_class.rb'), "class UtilClass\nend\n")

      create_package(@tmpdir, dependencies: %w[packs/feature packs/util])

      assert_raises(Boxwerk::LayerViolationError) { boot_system }
    end
  end
end
