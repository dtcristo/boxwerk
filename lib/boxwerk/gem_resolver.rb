# frozen_string_literal: true

require 'bundler'

module Boxwerk
  # Resolves per-package gem dependencies from lockfiles.
  # Parses lockfiles with Bundler::LockfileParser and resolves gem
  # load paths for $LOAD_PATH isolation per box.
  #
  # Unlike Bundler itself, this resolver can find gems outside the
  # current bundle by searching all gem installation directories.
  class GemResolver
    attr_reader :root_path

    def initialize(root_path)
      @root_path = root_path
      @all_specs = nil
    end

    # Returns an array of load paths for a package's gem dependencies.
    # Returns nil if the package has no gems.rb/Gemfile.
    def resolve_for(package)
      gemfile_path = find_gemfile(package)
      return nil unless gemfile_path

      lockfile_path = find_lockfile(gemfile_path)
      return nil unless lockfile_path && File.exist?(lockfile_path)

      resolve_from_lockfile(lockfile_path)
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

    # Parses a lockfile and resolves gem load paths.
    def resolve_from_lockfile(lockfile_path)
      lockfile_content = File.read(lockfile_path)
      parser = Bundler::LockfileParser.new(lockfile_content)

      paths = []
      parser.specs.each do |spec|
        gem_paths = resolve_gem_paths(spec.name, spec.version.to_s)
        paths.concat(gem_paths) if gem_paths
      end

      paths.uniq
    end

    # Resolves load paths for a specific gem version.
    # Searches all gem installation directories, bypassing Bundler's
    # filtering so that per-package gems can be found even when they
    # are not in the root bundle.
    def resolve_gem_paths(name, version)
      spec = find_gem_spec(name, version)
      unless spec
        # Don't warn about boxwerk itself (loaded via path: in development)
        warn "Boxwerk: gem '#{name}' (#{version}) not installed, skipping" unless name == 'boxwerk'
        return nil
      end
      collect_paths(spec)
    end

    # Finds a gem specification by searching all gem directories.
    # This works even under Bundler, which normally filters specs
    # to only those in the current bundle.
    def find_gem_spec(name, version)
      all_gem_specs.find { |s| s.name == name && s.version.to_s == version } ||
        all_gem_specs.find { |s| s.name == name }
    end

    # Loads all gem specifications from all gem directories.
    # Cached for the lifetime of this resolver.
    def all_gem_specs
      @all_specs ||= begin
        dirs = Gem.path.flat_map { |p| Dir.glob(File.join(p, 'specifications', '*.gemspec')) }
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
        if dep_spec
          paths.concat(collect_paths(dep_spec, resolved))
        end
      end

      paths
    end
  end
end
