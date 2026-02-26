# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for per-package gem isolation via Gemfile and $LOAD_PATH isolation.
  class GemIsolationIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_per_package_gem_loading
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

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      parsed = root_box.eval('A::JsonUser.parse')
      assert_equal [1, 2, 3], parsed
    end

    def test_gem_isolation_between_packages
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

      create_package(@tmpdir, dependencies: %w[packages/a packages/b])

      result = boot_system

      root_box = result[:box_manager].boxes['.']
      assert_equal '1.0', root_box.eval('A::AService.version')
      assert_equal '2.0', root_box.eval('B::BService.version')
    end
  end
end
