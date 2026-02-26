# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class GemResolverTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_returns_nil_for_package_without_gemfile
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(File.join(pkg_dir, 'package.yml'), YAML.dump('enforce_dependencies' => true))

      pkg = Package.new(name: 'packs/a', config: {})
      resolver = GemResolver.new(@tmpdir)

      assert_nil resolver.resolve_for(pkg)
    end

    def test_detects_gemfile
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(File.join(pkg_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'json'\n")

      resolver = GemResolver.new(@tmpdir)
      # No lockfile, so returns nil
      pkg = Package.new(name: 'packs/a', config: {})
      assert_nil resolver.resolve_for(pkg)
    end

    def test_detects_gems_rb
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(File.join(pkg_dir, 'gems.rb'), "source 'https://rubygems.org'\ngem 'json'\n")

      resolver = GemResolver.new(@tmpdir)
      # gems.rb detected but no gems.locked, so returns nil
      pkg = Package.new(name: 'packs/a', config: {})
      assert_nil resolver.resolve_for(pkg)
    end

    def test_resolves_from_lockfile
      # Create a package with a real Gemfile.lock referencing an installed gem
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(File.join(pkg_dir, 'Gemfile'), "source 'https://rubygems.org'\ngem 'json'\n")

      # Get the actual installed json version
      json_spec = Gem::Specification.find_by_name('json')

      # Create a lockfile
      File.write(File.join(pkg_dir, 'Gemfile.lock'), <<~LOCK)
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

      pkg = Package.new(name: 'packs/a', config: {})
      resolver = GemResolver.new(@tmpdir)
      paths = resolver.resolve_for(pkg)

      assert paths.is_a?(Array)
      assert paths.any? { |p| p.include?('json') }
    end
  end
end
