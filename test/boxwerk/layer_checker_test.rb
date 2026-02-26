# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class LayerCheckerTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_reads_layers_from_packwerk_yml
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump(
        'layers' => %w[feature core utility],
      ))

      layers = LayerChecker.layers_for(@tmpdir)
      assert_equal %w[feature core utility], layers
    end

    def test_reads_deprecated_architecture_layers
      File.write(File.join(@tmpdir, 'packwerk.yml'), YAML.dump(
        'architecture_layers' => %w[product infrastructure],
      ))

      layers = LayerChecker.layers_for(@tmpdir)
      assert_equal %w[product infrastructure], layers
    end

    def test_empty_when_no_packwerk_yml
      assert_equal [], LayerChecker.layers_for(@tmpdir)
    end

    def test_enforces_layers_when_true
      pkg = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => true })
      assert LayerChecker.enforces_layers?(pkg)
    end

    def test_enforces_layers_when_strict
      pkg = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => 'strict' })
      assert LayerChecker.enforces_layers?(pkg)
    end

    def test_enforces_deprecated_architecture
      pkg = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_architecture' => true })
      assert LayerChecker.enforces_layers?(pkg)
    end

    def test_validate_allows_same_layer
      layers = %w[feature core utility]
      from = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => true, 'layer' => 'core' })
      to = Packwerk::Package.new(name: 'packages/b', config: { 'layer' => 'core' })

      assert_nil LayerChecker.validate_dependency(from, to, layers)
    end

    def test_validate_allows_lower_layer
      layers = %w[feature core utility]
      from = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => true, 'layer' => 'core' })
      to = Packwerk::Package.new(name: 'packages/b', config: { 'layer' => 'utility' })

      assert_nil LayerChecker.validate_dependency(from, to, layers)
    end

    def test_validate_blocks_higher_layer
      layers = %w[feature core utility]
      from = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => true, 'layer' => 'utility' })
      to = Packwerk::Package.new(name: 'packages/b', config: { 'layer' => 'feature' })

      error = LayerChecker.validate_dependency(from, to, layers)
      assert_match(/cannot depend on/, error)
      assert_match(/higher layer/, error)
    end

    def test_validate_allows_when_not_enforced
      layers = %w[feature core utility]
      from = Packwerk::Package.new(name: 'packages/a', config: { 'layer' => 'utility' })
      to = Packwerk::Package.new(name: 'packages/b', config: { 'layer' => 'feature' })

      assert_nil LayerChecker.validate_dependency(from, to, layers)
    end

    def test_validate_allows_when_no_layer_assigned
      layers = %w[feature core utility]
      from = Packwerk::Package.new(name: 'packages/a', config: { 'enforce_layers' => true })
      to = Packwerk::Package.new(name: 'packages/b', config: { 'layer' => 'feature' })

      assert_nil LayerChecker.validate_dependency(from, to, layers)
    end
  end
end
