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
      File.write(
        File.join(pkg_dir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )

      pkg = Package.new(name: 'packs/a', config: {})
      resolver = GemResolver.new(@tmpdir)

      assert_nil resolver.resolve_for(pkg)
    end

    def test_detects_gemfile
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      resolver = GemResolver.new(@tmpdir)
      # No lockfile, so returns nil
      pkg = Package.new(name: 'packs/a', config: {})
      assert_nil resolver.resolve_for(pkg)
    end

    def test_detects_gems_rb
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'gems.rb'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      resolver = GemResolver.new(@tmpdir)
      # gems.rb detected but no gems.locked, so returns nil
      pkg = Package.new(name: 'packs/a', config: {})
      assert_nil resolver.resolve_for(pkg)
    end

    def test_resolves_from_lockfile
      # Create a package with a real Gemfile.lock referencing an installed gem
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

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

    def test_gems_for_returns_gem_info_structs
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      json_spec = Gem::Specification.find_by_name('json')
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
      gems = resolver.gems_for(pkg)

      assert gems.is_a?(Array)
      assert_equal 1, gems.length
      assert_equal 'json', gems.first.name
      assert_equal json_spec.version.to_s, gems.first.version
      assert gems.first.load_paths.any? { |p| p.include?('json') }
    end

    def test_gems_for_caches_results
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      json_spec = Gem::Specification.find_by_name('json')
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

      result1 = resolver.gems_for(pkg)
      result2 = resolver.gems_for(pkg)
      assert_same result1, result2
    end

    def test_check_conflicts_empty_when_no_global_gems
      # Root package has no Gemfile, child has gems — no conflicts
      File.write(
        File.join(@tmpdir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )

      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      json_spec = Gem::Specification.find_by_name('json')
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

      gem_resolver = GemResolver.new(@tmpdir)
      pkg_resolver = PackageResolver.new(@tmpdir)

      conflicts = gem_resolver.check_conflicts(pkg_resolver)
      assert_empty conflicts
    end

    def test_check_conflicts_detects_global_override
      # Root and child both have json but at different versions
      json_spec = Gem::Specification.find_by_name('json')

      # Root Gemfile with json
      File.write(
        File.join(@tmpdir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )
      File.write(
        File.join(@tmpdir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )
      File.write(File.join(@tmpdir, 'Gemfile.lock'), <<~LOCK)
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

      # Child with a fake different version
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )
      File.write(File.join(pkg_dir, 'Gemfile.lock'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            json (99.99.99)

        PLATFORMS
          arm64-darwin-25

        DEPENDENCIES
          json

        BUNDLED WITH
           2.7.5
      LOCK

      gem_resolver = GemResolver.new(@tmpdir)
      pkg_resolver = PackageResolver.new(@tmpdir)

      # json 99.99.99 is in the lockfile but not installed, so it resolves
      # with no load paths but keeps its locked version — triggering a global
      # override conflict since root has the real version.
      conflicts = gem_resolver.check_conflicts(pkg_resolver)
      assert_equal 1, conflicts.length
      assert_equal :global_override, conflicts.first[:type]
      assert_equal 'json', conflicts.first[:gem_name]
      assert_equal '99.99.99', conflicts.first[:package_version]
      assert_equal 'packs/a', conflicts.first[:package]
    end

    def test_check_conflicts_no_conflict_when_same_version
      # Root and child both have json at the SAME version — no conflict
      json_spec = Gem::Specification.find_by_name('json')

      File.write(
        File.join(@tmpdir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )
      File.write(
        File.join(@tmpdir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )
      File.write(File.join(@tmpdir, 'Gemfile.lock'), <<~LOCK)
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

      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'package.yml'),
        YAML.dump('enforce_dependencies' => true),
      )
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )
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

      gem_resolver = GemResolver.new(@tmpdir)
      pkg_resolver = PackageResolver.new(@tmpdir)

      conflicts = gem_resolver.check_conflicts(pkg_resolver)
      assert_empty conflicts
    end

    def test_parse_gemfile_requires_default
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      resolver = GemResolver.new(@tmpdir)
      requires = resolver.parse_gemfile_requires(File.join(pkg_dir, 'Gemfile'))
      assert_nil requires['json']
    end

    def test_parse_gemfile_requires_false
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json', require: false\n",
      )

      resolver = GemResolver.new(@tmpdir)
      requires = resolver.parse_gemfile_requires(File.join(pkg_dir, 'Gemfile'))
      assert_equal [], requires['json']
    end

    def test_parse_gemfile_requires_custom
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'foo', require: 'foo/bar'\n",
      )

      resolver = GemResolver.new(@tmpdir)
      requires = resolver.parse_gemfile_requires(File.join(pkg_dir, 'Gemfile'))
      assert_equal ['foo/bar'], requires['foo']
    end

    def test_gems_for_includes_autorequire
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(
        File.join(pkg_dir, 'Gemfile'),
        "source 'https://rubygems.org'\ngem 'json'\n",
      )

      json_spec = Gem::Specification.find_by_name('json')
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
      gems = resolver.gems_for(pkg)

      assert_equal 1, gems.length
      # Gemfile entry with no require option → autorequire is :default
      assert_equal :default, gems.first.autorequire
    end

    # Other installed versions of a locked gem's dependency must not reach
    # the load path; the lockfile already pins the whole closure.
    def test_resolves_only_locked_versions
      write_locked_package(<<~SPECS)
        app (1.0)
          lib (~> 1.0)
        lib (1.0)
      SPECS
      resolver =
        resolver_with_installed(
          ["app", "1.0", { "lib" => "~> 1.0" }],
          %w[lib 1.5],
          %w[lib 1.0],
        )

      paths = resolver.resolve_for(Package.new(name: 'packs/a', config: {}))

      assert_equal [gem_lib('app-1.0'), gem_lib('lib-1.0')], paths
    end

    def test_skips_locked_version_that_is_not_installed
      write_locked_package(<<~SPECS)
        lib (1.2)
      SPECS
      resolver = resolver_with_installed(%w[lib 1.0], %w[lib 1.5])
      pkg = Package.new(name: 'packs/a', config: {})

      # Kernel#warn writes to its defining box's $stderr, which capture_io
      # cannot swap, so record warnings on the resolver.
      warnings = []
      resolver.define_singleton_method(:warn) { |message| warnings << message }

      assert_empty resolver.resolve_for(pkg)
      assert_equal ["Boxwerk: gem 'lib' (1.2) not installed, skipping"], warnings
    end

    private

    def write_locked_package(specs)
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      FileUtils.mkdir_p(pkg_dir)
      File.write(File.join(pkg_dir, 'Gemfile'), "gem 'app'\n")
      File.write(File.join(pkg_dir, 'Gemfile.lock'), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
        #{specs.gsub(/^/, '    ')}
        PLATFORMS
          ruby

        DEPENDENCIES
          app
      LOCK
    end

    # A resolver that sees only the given [name, version, deps] gems as installed.
    def resolver_with_installed(*installed)
      specs =
        installed.map do |name, version, deps = {}|
          Gem::Specification.new do |s|
            s.name = name
            s.version = version
            deps.each { |dep, req| s.add_runtime_dependency(dep, req) }
            s.loaded_from =
              File.join(@tmpdir, 'home', 'specifications', "#{name}-#{version}.gemspec")
          end
        end
      resolver = GemResolver.new(@tmpdir)
      resolver.define_singleton_method(:all_gem_specs) { specs }
      resolver
    end

    def gem_lib(dir)
      File.join(@tmpdir, 'home', 'gems', dir, 'lib')
    end
  end
end
