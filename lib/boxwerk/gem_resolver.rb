# frozen_string_literal: true

require 'bundler'

module Boxwerk
  # Resolves per-package gem dependencies from lockfiles.
  #
  # Parses lockfiles with Bundler::LockfileParser and resolves gem load paths
  # for $LOAD_PATH isolation per box. Unlike Bundler itself, this resolver can
  # find gems outside the current bundle by searching all gem directories.
  #
  # Gems are fully isolated per box — they do not leak across package
  # boundaries. Cross-package version conflicts are harmless because each box
  # has its own $LOAD_PATH and $LOADED_FEATURES snapshot. The only situation
  # worth flagging is when a package defines a gem that is also in the root
  # Gemfile at a different version: both versions end up in memory (the global
  # version inherited at box creation, the package version loaded on demand).
  class GemResolver
    # Represents a resolved gem for a package: name, version, load paths,
    # and autorequire directives from the Gemfile.
    #   autorequire: nil      → transitive dependency (not in Gemfile)
    #   autorequire: :default → require the gem name (Gemfile entry, no require option)
    #   autorequire: []       → skip (require: false)
    #   autorequire: ["x/y"]  → require each listed path
    GemInfo = Struct.new(:name, :version, :load_paths, :autorequire, keyword_init: true)

    attr_reader :root_path

    def initialize(root_path)
      @root_path = root_path
      @all_specs = nil
      @package_gems = {} # package name -> [GemInfo]
    end

    # Returns an array of load paths for a package's gem dependencies.
    # Returns nil if the package has no gems.rb/Gemfile.
    def resolve_for(package)
      gems = gems_for(package)
      return nil unless gems&.any?

      gems.flat_map(&:load_paths).uniq
    end

    # Returns [GemInfo] for a package, cached after first resolution.
    # Merges lockfile resolution with Gemfile autorequire directives.
    def gems_for(package)
      return @package_gems[package.name] if @package_gems.key?(package.name)

      gemfile_path = find_gemfile(package)
      unless gemfile_path
        @package_gems[package.name] = nil
        return nil
      end

      lockfile_path = find_lockfile(gemfile_path)
      unless lockfile_path && File.exist?(lockfile_path)
        @package_gems[package.name] = nil
        return nil
      end

      requires = parse_gemfile_requires(gemfile_path)
      gems = resolve_gems_from_lockfile(lockfile_path)
      gems.each do |g|
        next unless requires.key?(g.name)
        # :default means "require the gem name" (Gemfile entry with no require option).
        # nil means transitive dependency (not in Gemfile) — skip auto-require.
        g.autorequire = requires[g.name] || :default
      end
      @package_gems[package.name] = gems
      gems
    end

    # Parses the Gemfile to extract autorequire directives.
    # Returns { gem_name => autorequire_value } where value is:
    #   nil      → require the gem name (default)
    #   []       → skip (require: false)
    #   ["path"] → require the listed paths
    #
    # Uses a lightweight DSL evaluator to avoid Bundler::Dsl side-effects.
    def parse_gemfile_requires(gemfile_path)
      parser = GemfileRequireParser.new
      parser.eval_gemfile(gemfile_path)
      parser.requires
    end

    # Checks for gem version conflicts between global and per-package gems.
    # Returns an array of conflict descriptions (empty if none).
    #
    # Cross-package conflicts are NOT checked because gems are fully isolated
    # per box — each box has its own $LOAD_PATH and $LOADED_FEATURES snapshot.
    # Package A can safely use gem Z v2 while package B uses gem Z v1, even if
    # A depends on B.
    #
    # The only conflict worth flagging is a **global override**: a package
    # defines a gem that is also in the root Gemfile at a different version.
    # Both versions load into memory (global inherited at box creation,
    # package version loaded on demand), which wastes memory but is
    # functionally correct.
    def check_conflicts(package_resolver)
      conflicts = []

      root_gems = gems_for(package_resolver.root)
      return conflicts unless root_gems&.any?

      root_gem_map = root_gems.each_with_object({}) { |g, h| h[g.name] = g }

      package_resolver.packages.each_value do |pkg|
        next if pkg.root?

        pkg_gems = gems_for(pkg)
        next unless pkg_gems

        pkg_gems.each do |gem_info|
          root_gem = root_gem_map[gem_info.name]
          next unless root_gem
          next if root_gem.version == gem_info.version

          conflicts << {
            type: :global_override,
            gem_name: gem_info.name,
            package: pkg.name,
            package_version: gem_info.version,
            global_version: root_gem.version,
          }
        end
      end

      conflicts
    end

    private

    def package_dir(package)
      if package.root?
        @root_path
      else
        File.join(@root_path, package.name)
      end
    end

    def find_gemfile(package)
      dir = package_dir(package)

      gemfile = File.join(dir, 'gems.rb')
      return gemfile if File.exist?(gemfile)

      gemfile = File.join(dir, 'Gemfile')
      return gemfile if File.exist?(gemfile)

      nil
    end

    def find_lockfile(gemfile_path)
      if gemfile_path.end_with?('gems.rb')
        gemfile_path.sub('gems.rb', 'gems.locked')
      else
        "#{gemfile_path}.lock"
      end
    end

    # Parses a lockfile and returns [GemInfo] with resolved load paths.
    def resolve_gems_from_lockfile(lockfile_path)
      lockfile_content = File.read(lockfile_path)
      parser = Bundler::LockfileParser.new(lockfile_content)

      gems = []
      parser.specs.each do |spec|
        paths = resolve_gem_paths(spec.name, spec.version.to_s)
        next unless paths

        gems << GemInfo.new(
          name: spec.name,
          version: spec.version.to_s,
          load_paths: paths,
        )
      end

      gems
    end

    # Resolves load paths for a specific gem version.
    def resolve_gem_paths(name, version)
      spec = find_gem_spec(name, version)
      unless spec
        unless name == 'boxwerk'
          warn "Boxwerk: gem '#{name}' (#{version}) not installed, skipping"
        end
        return nil
      end
      collect_paths(spec)
    end

    # Finds a gem specification by searching all gem directories.
    def find_gem_spec(name, version)
      all_gem_specs.find { |s| s.name == name && s.version.to_s == version } ||
        all_gem_specs.find { |s| s.name == name }
    end

    # Loads all gem specifications from all gem directories.
    # Cached for the lifetime of this resolver.
    def all_gem_specs
      @all_specs ||=
        begin
          dirs =
            Gem.path.flat_map do |p|
              Dir.glob(File.join(p, 'specifications', '*.gemspec'))
            end
          dirs.map { |path| Gem::Specification.load(path) }.compact
        end
    end

    # Recursively collects load paths for a gem and its runtime dependencies.
    def collect_paths(spec, resolved = Set.new)
      return [] if resolved.include?(spec.name)

      resolved.add(spec.name)
      paths = spec.full_require_paths.dup

      spec.runtime_dependencies.each do |dep|
        dep_spec = find_gem_spec(dep.name, dep.requirement.to_s.delete('= '))
        dep_spec ||= all_gem_specs.find { |s| s.name == dep.name }
        paths.concat(collect_paths(dep_spec, resolved)) if dep_spec
      end

      paths
    end
  end
end
