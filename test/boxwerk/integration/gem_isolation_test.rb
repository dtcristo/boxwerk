# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for per-package gem isolation via Gemfile and $LOAD_PATH isolation.
  class GemIsolationIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_per_package_gem_loading_with_real_gem
      a_dir = create_package_dir('a')
      create_package(a_dir)

      json_spec = Gem::Specification.find_by_name('json')
      File.write(File.join(a_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'json'\n")
      File.write(File.join(a_dir, 'Gemfile.lock'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            json (#{json_spec.version})

        PLATFORMS
          arm64-darwin-25

        DEPENDENCIES
          json

        BUNDLED WITH
           2.7.5
      LOCK

      File.write(
        File.join(a_dir, 'lib', 'json_user.rb'),
        "class JsonUser\n  def self.parse\n    require 'json'\n    JSON.parse('[1,2,3]')\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      parsed = root_box.eval('JsonUser.parse')
      assert_equal [1, 2, 3], parsed
    end

    def test_different_load_paths_per_box
      # Two packages with different versions of the same "gem" (simulated)
      a_dir = create_package_dir('a')
      create_package(a_dir)

      b_dir = create_package_dir('b')
      create_package(b_dir)

      a_gem_dir = File.join(@tmpdir, 'gems_v1', 'lib')
      FileUtils.mkdir_p(a_gem_dir)
      File.write(File.join(a_gem_dir, 'my_lib.rb'), "module MyLib\n  VERSION = '1.0'\nend\n")

      b_gem_dir = File.join(@tmpdir, 'gems_v2', 'lib')
      FileUtils.mkdir_p(b_gem_dir)
      File.write(File.join(b_gem_dir, 'my_lib.rb'), "module MyLib\n  VERSION = '2.0'\nend\n")

      File.write(
        File.join(a_dir, 'lib', 'a_service.rb'),
        "class AService\n  def self.version\n    $LOAD_PATH.unshift('#{a_gem_dir}')\n    require 'my_lib'\n    MyLib::VERSION\n  end\nend\n",
      )

      File.write(
        File.join(b_dir, 'lib', 'b_service.rb'),
        "class BService\n  def self.version\n    $LOAD_PATH.unshift('#{b_gem_dir}')\n    require 'my_lib'\n    MyLib::VERSION\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      assert_equal '1.0', root_box.eval('AService.version')
      assert_equal '2.0', root_box.eval('BService.version')
    end

    def test_gem_load_path_isolated_per_box
      # Verify $LOAD_PATH is truly isolated between boxes
      a_dir = create_package_dir('a')
      create_package(a_dir)

      b_dir = create_package_dir('b')
      create_package(b_dir)

      gem_dir = File.join(@tmpdir, 'only_a_gem', 'lib')
      FileUtils.mkdir_p(gem_dir)
      File.write(File.join(gem_dir, 'exclusive.rb'), "module Exclusive\n  VALUE = 'only_a'\nend\n")

      json_spec = Gem::Specification.find_by_name('json')
      File.write(File.join(a_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'json'\n")
      File.write(File.join(a_dir, 'Gemfile.lock'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            json (#{json_spec.version})

        PLATFORMS
          arm64-darwin-25

        DEPENDENCIES
          json

        BUNDLED WITH
           2.7.5
      LOCK

      File.write(
        File.join(a_dir, 'lib', 'loader.rb'),
        "class Loader\n  def self.load_path_count\n    $LOAD_PATH.size\n  end\nend\n",
      )

      File.write(
        File.join(b_dir, 'lib', 'loader.rb'),
        "class Loader\n  def self.load_path_count\n    $LOAD_PATH.size\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: %w[packs/a packs/b])

      result = boot_system

      a_box = result[:box_manager].boxes['packs/a']
      b_box = result[:box_manager].boxes['packs/b']

      # A has gem load paths added, B does not — their $LOAD_PATHs should differ
      a_count = a_box.eval('$LOAD_PATH.size')
      b_count = b_box.eval('$LOAD_PATH.size')
      assert_operator a_count, :>, b_count,
                      'Package A should have more load paths than B (gem paths added)'
    end

    def test_package_without_gemfile_has_no_extra_load_paths
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'simple.rb'),
        "class Simple\n  def self.value\n    'no_gems'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'no_gems', root_box.eval('Simple.value')
    end

    def test_gems_rb_format_detected
      a_dir = create_package_dir('a')
      create_package(a_dir)

      # Use gems.rb/gems.locked naming convention
      json_spec = Gem::Specification.find_by_name('json')
      File.write(File.join(a_dir, 'gems.rb'), "source 'https://rubygems.org'\ngem 'json'\n")
      File.write(File.join(a_dir, 'gems.locked'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            json (#{json_spec.version})

        PLATFORMS
          arm64-darwin-25

        DEPENDENCIES
          json

        BUNDLED WITH
           2.7.5
      LOCK

      File.write(
        File.join(a_dir, 'lib', 'json_user.rb'),
        "class JsonUser\n  def self.parse\n    require 'json'\n    JSON.parse('{\"a\":1}')\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']
      parsed = root_box.eval('JsonUser.parse')
      assert_equal({ 'a' => 1 }, parsed)
    end
  end
end
