# frozen_string_literal: true

module Boxwerk
  # BoxManager creates a Ruby::Box for each package and wires them together.
  #
  # Boot sequence for each package (in topological order):
  #   1. Create Ruby::Box
  #   2. Configure per-package gem load paths (if Gemfile present)
  #   3. Build file index — scan lib/ for .rb files, map to constant names
  #   4. Register autoload entries — constants loaded on first access
  #   5. Wire dependency constants, enforcing:
  #      - Constant privacy (public_path, private_constants)
  #
  # No code is loaded eagerly. Constants are resolved on first access via
  # Ruby's autoload mechanism (intra-package) or const_missing proxies
  # (cross-package). Resolved constants are cached via const_set.
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

    # Boot a single package: create box, set up gems, build file index,
    # set up autoloader, wire dependencies. No code is loaded eagerly.
    def boot(package, resolver)
      return if @boxes.key?(package.name)

      box = Ruby::Box.new
      @boxes[package.name] = box

      # Set up per-package gem load paths
      setup_gem_load_paths(box, package)

      # Build file index (scan directories, don't load any code)
      file_index = build_file_index(package)
      @file_indexes[package.name] = file_index

      # Set up autoloader for intra-package constant resolution
      setup_autoloader(box, file_index)

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

    # Scans package directories and maps constant names to file paths
    # using Zeitwerk naming conventions. Does not load any code.
    def build_file_index(package)
      index = {}

      pub_path = if PrivacyChecker.enforces_privacy?(package)
                   PrivacyChecker.public_path_for(package, @root_path)
                 end

      lib_path = package_lib_path(package)
      if lib_path && File.directory?(lib_path)
        scan_for_constants(lib_path, index, exclude: pub_path)
      end

      # Scan public_path as a separate autoload root so that
      # public/invoice.rb maps to Invoice (not Public::Invoice).
      if pub_path && File.directory?(pub_path)
        scan_for_constants(pub_path, index)
      end

      index
    end

    def scan_for_constants(dir, index, exclude: nil)
      base = dir.end_with?('/') ? dir : "#{dir}/"
      Dir.glob(File.join(dir, '**', '*.rb')).sort.each do |file|
        next if exclude && file.start_with?(exclude)

        relative = file.delete_prefix(base).delete_suffix('.rb')
        const_name = relative.split('/').map { |part| Boxwerk.camelize(part) }.join('::')
        index[const_name] = file
      end
    end

    # Registers autoload entries in the box for intra-package lazy loading.
    def setup_autoloader(box, file_index)
      file_index.each do |const_name, file_path|
        if const_name.include?('::')
          parts = const_name.split('::')
          # Ensure parent modules exist
          parts[0..-2].each_with_index do |_, i|
            mod_path = parts[0..i].join('::')
            box.eval("#{mod_path} = Module.new unless defined?(#{mod_path})")
          end
          parent = parts[0..-2].join('::')
          child = parts.last
          box.eval("#{parent}.autoload :#{child}, #{file_path.inspect}")
        else
          box.eval("autoload :#{const_name}, #{file_path.inspect}")
        end
      end
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
