# frozen_string_literal: true

module Boxwerk
  # BoxManager creates a Ruby::Box for each package and wires them together.
  #
  # Boot sequence for each package (in topological order):
  #   1. Create Ruby::Box
  #   2. Configure per-package gem load paths (if Gemfile present)
  #   3. Auto-require gems from Gemfile (non-root packages)
  #   4. Scan default directories with Zeitwerk (lib/ + public/)
  #   5. Register autoload entries in the box
  #   6. Run optional per-package boot.rb in the box
  #   7. Scan any additional autoload dirs configured in boot.rb
  #   8. Wire dependency constants, enforcing:
  #      - Constant privacy (public_path, private_constants)
  #
  # Zeitwerk is used for file scanning and inflection only. Autoload
  # registration is done directly via box.eval because Zeitwerk's own
  # autoload calls execute in the root box context (where Zeitwerk was
  # loaded), not the target package box.
  class BoxManager
    attr_reader :boxes, :gem_resolver

    def initialize(root_path)
      @root_path = root_path
      @boxes = {} # package name -> Ruby::Box
      @file_indexes = {} # package name -> {const_name => abs_path}
      @gem_resolver = GemResolver.new(root_path)
    end

    # Boot all packages in topological order.
    def boot_all(resolver)
      order = resolver.topological_order

      order.each { |package| boot(package, resolver) }
    end

    # Boot a single package: create box, set up gems, scan with Zeitwerk,
    # run boot.rb, register additional dirs, wire dependencies.
    def boot(package, resolver)
      return if @boxes.key?(package.name)

      box = Ruby::Box.new
      @boxes[package.name] = box

      # Set up per-package gem load paths
      setup_gem_load_paths(box, package)

      # Auto-require gems declared in the package Gemfile
      auto_require_gems(box, package)

      # Scan default directories and register autoloads
      file_index = scan_and_register(box, package)

      # Run optional per-package boot.rb, then scan additional dirs
      extra_index = run_package_boot(box, package)
      file_index.merge!(extra_index) if extra_index

      @file_indexes[package.name] = file_index

      # Wire dependency constants into this box
      wire_dependency_constants(box, package, resolver)
    end

    private

    def setup_gem_load_paths(box, package)
      gem_paths = @gem_resolver.resolve_for(package)
      return unless gem_paths&.any?

      gem_paths.each { |path| box.eval("$LOAD_PATH.unshift(#{path.inspect})") }
    end

    # Auto-require gems based on Gemfile autorequire directives.
    # Mirrors Bundler's default behavior: gems are required unless
    # `require: false` is specified. Skips the root package since its
    # gems are already loaded globally by Bundler. Only auto-requires
    # gems explicitly declared in the Gemfile, not transitive dependencies.
    def auto_require_gems(box, package)
      return if package.root?

      gems = @gem_resolver.gems_for(package)
      return unless gems&.any?

      gems.each do |gem_info|
        next if gem_info.name == 'boxwerk'
        next unless gem_info.autorequire.is_a?(Array) || gem_info.autorequire == :default

        paths = gem_require_paths(gem_info)
        next unless paths

        paths.each do |path|
          box.eval(<<~RUBY)
            begin
              require #{path.inspect}
            rescue LoadError
            end
          RUBY
        end
      end
    end

    # Returns the list of require paths for a gem, or nil to skip.
    def gem_require_paths(gem_info)
      case gem_info.autorequire
      when :default then [gem_info.name]
      when []       then nil
      else               gem_info.autorequire
      end
    end

    # Scans package directories with ZeitwerkScanner and registers autoloads
    # in the box. Returns a file index for use by ConstantResolver.
    def scan_and_register(box, package)
      all_entries = []

      # Always compute public path for file scanning. Privacy enforcement
      # controls access, not discovery — files in public/ are always scanned.
      pub_path = PrivacyChecker.public_path_for(package, @root_path)

      lib_path = package_lib_path(package)
      if lib_path && File.directory?(lib_path)
        entries = ZeitwerkScanner.scan(lib_path)
        # Exclude constants under public_path (scanned separately)
        if pub_path && pub_path.start_with?(lib_path)
          entries =
            entries.reject do |e|
              e.file&.start_with?(pub_path) || e.dir&.start_with?(pub_path)
            end
        end
        all_entries.concat(entries)
      end

      # Scan public_path as a separate autoload root so that
      # public/invoice.rb maps to Invoice (not Public::Invoice).
      if pub_path && File.directory?(pub_path)
        all_entries.concat(ZeitwerkScanner.scan(pub_path))
      end

      ZeitwerkScanner.register_autoloads(box, all_entries)
      ZeitwerkScanner.build_file_index(all_entries)
    end

    # Runs the optional per-package boot.rb in the package's box context.
    # Injects BOXWERK_PACKAGE (PackageContext) for the boot script to use.
    # Returns additional file index entries from configured autoload dirs.
    def run_package_boot(box, package)
      pkg_dir = package_dir(package)
      boot_script = File.join(pkg_dir, 'boot.rb')
      return nil unless File.exist?(boot_script)

      # Build PackageContext with autoloader for this package
      autoloader = PackageContext::Autoloader.new(pkg_dir)
      context =
        PackageContext.new(
          name: package.name,
          root_path: pkg_dir,
          config: package.config,
          autoloader: autoloader,
        )

      # Inject PackageContext into the box
      box.const_set(:BOXWERK_PACKAGE, context)

      # Set thread-local so Boxwerk.package works during boot.rb
      Boxwerk.package = context

      # Run boot.rb in the package's box
      box.require(boot_script)

      # Clear thread-local after boot
      Boxwerk.package = nil

      # Read back config and apply additional autoload dirs
      apply_boot_config(box, package, autoloader)
    end

    # Reads autoload configuration from the PackageContext autoloader
    # and registers additional autoloads.
    def apply_boot_config(box, package, autoloader)
      pkg_dir = package_dir(package)
      all_entries = []

      autoloader.autoload_dirs.each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        all_entries.concat(ZeitwerkScanner.scan(abs_dir))
      end

      autoloader.collapse_dirs.each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir))
      end

      return nil if all_entries.empty?

      ZeitwerkScanner.register_autoloads(box, all_entries)
      ZeitwerkScanner.build_file_index(all_entries)
    end

    # Installs a const_missing handler on the box that searches dependency
    # boxes for the requested constant. When enforce_dependencies is false,
    # ALL packages are searchable (explicit deps first, then rest).
    # Privacy rules are still enforced per-dependency.
    def wire_dependency_constants(box, package, package_resolver)
      deps_config = []

      if package.enforce_dependencies?
        # Only search explicit dependencies
        search_packages = package_resolver.direct_dependencies(package)
      else
        # Search explicit deps first, then all remaining packages
        explicit = package_resolver.direct_dependencies(package)
        remaining =
          package_resolver
            .all_except(package)
            .reject { |p| explicit.include?(p) }
        search_packages = explicit + remaining
      end

      search_packages.each do |dep|
        dep_box = @boxes[dep.name]
        next unless dep_box

        dep_file_index = @file_indexes[dep.name] || {}

        pub_consts = PrivacyChecker.public_constants(dep, @root_path)
        priv_consts =
          (
            if PrivacyChecker.enforces_privacy?(dep)
              PrivacyChecker.private_constants_list(dep)
            else
              nil
            end
          )

        deps_config << {
          box: dep_box,
          file_index: dep_file_index,
          public_constants: pub_consts,
          private_constants: priv_consts,
          package_name: dep.name,
        }
      end

      return if deps_config.empty?

      # Pass references for lazy hint lookup — other packages may not
      # have been booted yet when this runs.
      dep_names = search_packages.map(&:name).to_set
      all_packages_ref = {
        file_indexes: @file_indexes,
        packages: package_resolver.packages,
        root_path: @root_path,
        dep_names: dep_names,
        self_name: package.name,
      }

      ConstantResolver.install_dependency_resolver(
        box,
        deps_config,
        all_packages_ref: all_packages_ref,
        package_name: package.name,
      )
    end

    def package_dir(package)
      if package.root?
        @root_path
      else
        File.join(@root_path, package.name)
      end
    end

    def package_lib_path(package)
      if package.root?
        nil
      else
        File.join(@root_path, package.name, 'lib')
      end
    end
  end
end
