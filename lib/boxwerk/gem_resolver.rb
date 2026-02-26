# frozen_string_literal: true

require 'bundler'

module Boxwerk
  # Resolves per-package gem dependencies from Gemfile.lock.
  # Parses lockfiles with Bundler::LockfileParser and resolves gem
  # load paths via Gem::Specification for $LOAD_PATH isolation per box.
  class GemResolver
    attr_reader :root_path

    def initialize(root_path)
      @root_path = root_path
    end

    # Returns an array of load paths for a package's gem dependencies.
    # Returns nil if the package has no Gemfile.
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

    # Finds a Gemfile or gems.rb for the package.
    def find_gemfile(package)
      dir = package_dir(package)

      # Check for gems.rb first (modern convention), then Gemfile
      gemfile = File.join(dir, 'gems.rb')
      return gemfile if File.exist?(gemfile)

      gemfile = File.join(dir, 'Gemfile')
      return gemfile if File.exist?(gemfile)

      nil
    end

    # Finds the lockfile corresponding to a gemfile.
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

    # Resolves load paths for a specific gem version and its runtime dependencies.
    def resolve_gem_paths(name, version)
      spec = Gem::Specification.find_by_name(name, "= #{version}")
      collect_paths(spec)
    rescue Gem::MissingSpecError
      # Gem not installed at this version, try without version constraint
      begin
        spec = Gem::Specification.find_by_name(name)
        collect_paths(spec)
      rescue Gem::MissingSpecError
        warn "Boxwerk: gem '#{name}' (#{version}) not installed, skipping"
        nil
      end
    end

    # Recursively collects load paths for a gem and its runtime dependencies.
    def collect_paths(spec, resolved = Set.new)
      return [] if resolved.include?(spec.name)

      resolved.add(spec.name)
      paths = spec.full_require_paths.dup

      spec.runtime_dependencies.each do |dep|
        begin
          dep_spec = dep.to_spec
          paths.concat(collect_paths(dep_spec, resolved))
        rescue Gem::MissingSpecError
          # Skip missing optional dependencies
        end
      end

      paths
    end
  end
end
