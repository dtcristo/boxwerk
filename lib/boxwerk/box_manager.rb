# frozen_string_literal: true

module Boxwerk
  # BoxManager creates a Ruby::Box for each package and wires them together.
  #
  # Boot sequence for each package (in topological order):
  #   1. Create Ruby::Box
  #   2. Configure per-package gem load paths (if Gemfile present)
  #   3. Scan directories with Zeitwerk (file discovery + inflection)
  #   4. Register autoload entries in the box
  #   5. Wire dependency constants, enforcing:
  #      - Constant privacy (public_path, private_constants)
  #
  # Zeitwerk is used for file scanning and inflection only. Autoload
  # registration is done directly via box.eval because Zeitwerk's own
  # autoload calls execute in the root box context (where Zeitwerk was
  # loaded), not the target package box.
  class BoxManager
    attr_reader :boxes

    def initialize(root_path)
      @root_path = root_path
      @boxes = {} # package name -> Ruby::Box
      @file_indexes = {} # package name -> {const_name => abs_path}
      @gem_resolver = GemResolver.new(root_path)
    end

    # Boot all packages in topological order.
    def boot_all(resolver)
      order = resolver.topological_order

      order.each do |package|
        boot(package, resolver)
      end
    end

    # Boot a single package: create box, set up gems, scan with Zeitwerk,
    # register autoloads, wire dependencies.
    def boot(package, resolver)
      return if @boxes.key?(package.name)

      box = Ruby::Box.new
      @boxes[package.name] = box

      # Set up per-package gem load paths
      setup_gem_load_paths(box, package)

      # Scan directories and register autoloads
      file_index = scan_and_register(box, package)
      @file_indexes[package.name] = file_index

      # Wire dependency constants into this box
      wire_dependency_constants(box, package, resolver)
    end

    private

    def setup_gem_load_paths(box, package)
      gem_paths = @gem_resolver.resolve_for(package)
      return unless gem_paths&.any?

      gem_paths.each do |path|
        box.eval("$LOAD_PATH.unshift(#{path.inspect})")
      end
    end

    # Scans package directories with ZeitwerkScanner and registers autoloads
    # in the box. Returns a file index for use by ConstantResolver.
    def scan_and_register(box, package)
      all_entries = []

      pub_path = if PrivacyChecker.enforces_privacy?(package)
                   PrivacyChecker.public_path_for(package, @root_path)
                 end

      lib_path = package_lib_path(package)
      if lib_path && File.directory?(lib_path)
        entries = ZeitwerkScanner.scan(lib_path)
        # Exclude constants under public_path (scanned separately)
        if pub_path && pub_path.start_with?(lib_path)
          entries = entries.reject { |e| e.file&.start_with?(pub_path) || e.dir&.start_with?(pub_path) }
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

    # Installs a const_missing handler on the box that searches all direct
    # dependency boxes for the requested constant. Constants are NOT wrapped
    # in a namespace — they are accessible directly (e.g. Invoice, not
    # Finance::Invoice). Privacy rules are enforced per-dependency.
    def wire_dependency_constants(box, package, package_resolver)
      deps_config = []

      package_resolver.direct_dependencies(package).each do |dep|
        dep_box = @boxes[dep.name]
        next unless dep_box

        dep_file_index = @file_indexes[dep.name] || {}

        pub_consts = PrivacyChecker.public_constants(dep, @root_path)
        priv_consts = PrivacyChecker.enforces_privacy?(dep) ?
          PrivacyChecker.private_constants_list(dep) : nil

        deps_config << {
          box: dep_box,
          file_index: dep_file_index,
          public_constants: pub_consts,
          private_constants: priv_consts,
          package_name: dep.name,
        }
      end

      return if deps_config.empty?

      ConstantResolver.install_dependency_resolver(box, deps_config)
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
