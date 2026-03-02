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
    attr_reader :boxes, :gem_resolver, :file_indexes, :default_autoload_dirs, :package_dirs_info

    def initialize(root_path)
      @root_path = root_path
      @boxes = {} # package name -> Ruby::Box
      @file_indexes = {} # package name -> {const_name => abs_path}
      @gem_resolver = GemResolver.new(root_path)
      @default_autoload_dirs = {} # package name -> [relative dir strings]
      @package_dirs_info = {} # package name -> { autoload: [...], collapse: [...], ignore: [...] }
    end

    # Boot all packages in topological order.
    def boot_all(resolver, eager_load_packages: false)
      resolver.topological_order.each do |package|
        boot(package, resolver)
        next unless eager_load_packages

        box = @boxes[package.name]
        file_index = @file_indexes[package.name] || {}
        eager_load_box(box, file_index) if box
      end
    end

    # Boot only the target package and its transitive dependencies.
    # If the target (or any dep) has no enforce_dependencies, boot all
    # packages since it may need to access constants from any of them.
    def boot_package(target, resolver, eager_load_packages: false)
      packages_to_boot = collect_transitive_deps(target, resolver, Set.new)
      packages_to_boot << target unless packages_to_boot.include?(target)

      # If any package in the set doesn't enforce dependencies, it can
      # access constants from all packages — boot everything.
      if packages_to_boot.any? { |p| !p.enforce_dependencies? }
        packages_to_boot = resolver.topological_order.to_set
      end

      # Boot in dependency order (deps first)
      ordered =
        resolver.topological_order.select { |p| packages_to_boot.include?(p) }
      ordered.each do |package|
        boot(package, resolver)
        next unless eager_load_packages

        box = @boxes[package.name]
        file_index = @file_indexes[package.name] || {}
        eager_load_box(box, file_index) if box
      end
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

      # Scan default directories and register autoloads. Returns default dirs
      # so they can be injected into the PackageContext autoloader.
      file_index, default_dirs = scan_and_register(box, package)

      # Set BOXWERK_PACKAGE constant in the box for Boxwerk.package access.
      # Pass default_dirs so Boxwerk.package.autoloader.autoload_dirs reflects them.
      set_package_context(box, package, default_dirs: default_dirs)

      # Run optional per-package boot.rb, then scan additional dirs
      extra_index = run_package_boot(box, package, file_index)
      file_index.merge!(extra_index) if extra_index

      @file_indexes[package.name] = file_index

      # Record all dir info for use by the info command
      record_package_dirs(box, package, default_dirs)

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
    # in the box. Returns [file_index, default_dirs] where default_dirs is
    # the list of relative dir strings scanned (e.g. ['lib/', 'public/']).
    def scan_and_register(box, package)
      all_entries = []
      default_al_dirs = []

      # Always compute public path for file scanning. Privacy enforcement
      # controls access, not discovery — files in public/ are always scanned.
      pub_path = PrivacyChecker.public_path_for(package, @root_path)

      lib_path = package_lib_path(package)
      if lib_path && File.directory?(lib_path)
        default_al_dirs << 'lib/'
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
        pub_rel = package.config['public_path'] || 'public/'
        pub_rel = "#{pub_rel}/" unless pub_rel.end_with?('/')
        default_al_dirs << pub_rel
        all_entries.concat(ZeitwerkScanner.scan(pub_path))
      end

      ZeitwerkScanner.register_autoloads(box, all_entries)
      @default_autoload_dirs[package.name] = default_al_dirs

      [ZeitwerkScanner.build_file_index(all_entries), default_al_dirs]
    end

    # Runs the optional per-package boot.rb in the package's box context.
    # Returns additional file index entries from configured autoload dirs.
    def run_package_boot(box, package, file_index)
      pkg_dir = package_dir(package)
      boot_script = File.join(pkg_dir, 'boot.rb')
      return nil unless File.exist?(boot_script)

      # Retrieve autoloader from the PackageContext already set on the box
      context = box.const_get(:BOXWERK_PACKAGE)
      autoloader = context.autoloader

      # Run boot.rb in the package's box
      box.require(boot_script)

      # Read back config and apply additional autoload dirs
      apply_boot_config(box, package, autoloader, file_index)
    end

    # Reads autoload configuration from the PackageContext autoloader
    # and returns the merged file index. Dirs already registered via
    # autoloader.setup (auto-called by push_dir/collapse during boot.rb)
    # are included via accumulated_file_index. Any remaining unregistered
    # dirs are registered here. Also applies ignore_dirs and collapse
    # cleanup (removes intermediate namespaces registered during scan_and_register).
    def apply_boot_config(box, package, autoloader, file_index)
      pkg_dir = package_dir(package)
      all_entries = []

      autoloader.user_autoload_dirs[autoloader.push_setup_count..].each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        all_entries.concat(ZeitwerkScanner.scan(abs_dir))
      end

      autoloader.user_collapse_dirs[autoloader.collapse_setup_count..].each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        root_dir = autoloader.find_root_for(abs_dir)
        all_entries.concat(ZeitwerkScanner.scan_files_only(abs_dir, root_dir: root_dir))
      end

      new_index =
        if all_entries.empty?
          {}
        else
          ZeitwerkScanner.register_autoloads(box, all_entries)
          ZeitwerkScanner.build_file_index(all_entries)
        end

      # Remove intermediate namespaces for collapsed dirs (e.g. Analytics::Formatters)
      autoloader.all_collapse_dirs.each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        root_dir = autoloader.find_root_for(abs_dir)
        next unless root_dir
        remove_namespace_for_dir(box, abs_dir, root_dir, file_index)
      end

      # Remove constants registered for ignored dirs
      autoloader.user_ignore_dirs.each do |dir|
        abs_dir = File.expand_path(dir, pkg_dir)
        next unless File.directory?(abs_dir)
        root_dir = autoloader.find_root_for(abs_dir)
        remove_namespace_for_dir(box, abs_dir, root_dir, file_index)
      end

      # Merge any file index entries accumulated during auto-setup calls
      accumulated = autoloader.accumulated_file_index
      combined = accumulated.merge(new_index)
      combined.empty? ? nil : combined
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

      # Always install a resolver so that NameError hints work even when
      # there are no declared dependencies.
      return if deps_config.empty? && package_resolver.packages.size <= 1

      ConstantResolver.install_dependency_resolver(
        box,
        deps_config,
        all_packages_ref: all_packages_ref,
        package_name: package.name,
      )
    end

    # Sets the BOXWERK_PACKAGE constant in the box with a PackageContext
    # and overrides Boxwerk.package in the box to return it.
    # default_dirs: relative autoload dir strings from scan_and_register
    # (e.g. ['lib/', 'public/']), injected into the autoloader so that
    # Boxwerk.package.autoloader.autoload_dirs includes them.
    def set_package_context(box, package, default_dirs: [])
      pkg_dir = package_dir(package)
      autoloader = PackageContext::Autoloader.new(pkg_dir, box: box)
      autoloader.set_defaults(autoload_dirs: default_dirs)
      context =
        PackageContext.new(
          name: package.name,
          root_path: pkg_dir,
          config: package.config,
          autoloader: autoloader,
        )
      box.const_set(:BOXWERK_PACKAGE, context)

      # Override Boxwerk.package in this box so it returns the box's
      # own BOXWERK_PACKAGE. Monkey patch isolation ensures this only
      # affects this box.
      box.eval(<<~RUBY)
        module Boxwerk
          def self.package
            BOXWERK_PACKAGE
          end
        end
      RUBY
    end

    # Eager-loads all constants in a box by requiring every file in
    # the file index.
    def eager_load_box(box, file_index)
      file_index.each_value do |file|
        next unless file
        box.require(file)
      end
    end

    # Recursively collects all transitive dependencies of a package.
    def collect_transitive_deps(package, resolver, visited)
      deps = Set.new
      package.dependencies.each do |dep_name|
        next if visited.include?(dep_name)
        visited.add(dep_name)
        dep = resolver.packages[dep_name]
        next unless dep
        deps.add(dep)
        deps.merge(collect_transitive_deps(dep, resolver, visited))
      end
      deps
    end

    def package_dir(package)
      if package.root?
        @root_path
      else
        File.join(@root_path, package.name)
      end
    end

    # Records all autoload/collapse/ignore dirs for a package after boot.
    # Used by the info command.
    def record_package_dirs(box, package, default_dirs)
      al = box.const_get(:BOXWERK_PACKAGE)&.autoloader rescue nil
      pkg_dir = package_dir(package)
      @package_dirs_info[package.name] = {
        autoload: default_dirs + (al&.user_autoload_dirs&.map { |d| normalize_for_info(d, pkg_dir) } || []),
        collapse: (al&.user_collapse_dirs&.map { |d| normalize_for_info(d, pkg_dir) } || []),
        ignore:   (al&.user_ignore_dirs&.map { |d| normalize_for_info(d, pkg_dir) } || []),
      }
    end

    # Converts an absolute path to a relative dir string (with trailing slash),
    # or returns the relative string as-is.
    def normalize_for_info(dir, base_path)
      if dir.start_with?('/')
        rel = dir.delete_prefix("#{base_path}/")
        rel == dir ? dir : "#{rel.chomp('/')}/"
      else
        "#{dir.chomp('/')}/"
      end
    end

    def package_lib_path(package)
      if package.root?
        nil
      else
        File.join(@root_path, package.name, 'lib')
      end
    end

    # Removes a directory's namespace constant (and its children) from the box.
    # Used for collapse (removes intermediate namespace) and ignore (removes namespace).
    # Also removes matching entries from file_index.
    def remove_namespace_for_dir(box, abs_dir, root_dir, file_index)
      inflector = Zeitwerk::Inflector.new
      rel = abs_dir.delete_prefix("#{root_dir}/")
      parts = rel.split('/')
      ns_cnames = parts.map { |p| inflector.camelize(p, root_dir) }
      parent_ns = ns_cnames[0...-1].join('::')
      ns_cname = ns_cnames.last
      ns_full = ns_cnames.join('::')

      # Remove the constant from the box (works for both autoloads and defined constants)
      if parent_ns.empty?
        box.eval("remove_const(:#{ns_cname}) rescue nil")
      else
        box.eval("#{parent_ns}.send(:remove_const, :#{ns_cname}) rescue nil")
      end

      # Remove all file_index entries under this namespace
      file_index.reject! { |k, _| k == ns_full || k.start_with?("#{ns_full}::") }
    end
  end
end
