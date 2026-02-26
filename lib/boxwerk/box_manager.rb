# frozen_string_literal: true

module Boxwerk
  # BoxManager creates Ruby::Box instances for packages, loads their code,
  # injects namespace proxy modules for dependencies, and boots in topological order.
  # Enforces visibility, folder privacy, layer, and privacy constraints.
  class BoxManager
    attr_reader :boxes

    def initialize(root_path)
      @root_path = root_path
      @boxes = {} # package name -> Ruby::Box
      @gem_resolver = GemResolver.new(root_path)
      @layers = LayerChecker.layers_for(root_path)
    end

    # Boot all packages in topological order.
    def boot_all(resolver)
      order = resolver.topological_order

      order.each do |package|
        boot(package, resolver)
      end
    end

    # Boot a single package: create box, set up gems, load code, wire dependencies.
    def boot(package, resolver)
      return if @boxes.key?(package.name)

      box = Ruby::Box.new
      @boxes[package.name] = box

      # Set up per-package gem load paths
      setup_gem_load_paths(box, package)

      # Load package code into the box
      load_package_code(box, package)

      # Wire namespace proxies for each direct dependency
      wire_dependency_namespaces(box, package, resolver)
    end

    private

    def setup_gem_load_paths(box, package)
      gem_paths = @gem_resolver.resolve_for(package)
      return unless gem_paths&.any?

      gem_paths.each do |path|
        box.eval("$LOAD_PATH.unshift(#{path.inspect})")
      end
    end

    def load_package_code(box, package)
      lib_path = package_lib_path(package)
      if lib_path && File.directory?(lib_path)
        Dir.glob(File.join(lib_path, '**', '*.rb')).sort.each do |file|
          box.require(file)
        end
      end

      # Also load files from public_path (if different from lib/)
      if PrivacyChecker.enforces_privacy?(package)
        pub_path = PrivacyChecker.public_path_for(package, @root_path)
        if pub_path && File.directory?(pub_path) && pub_path != lib_path
          Dir.glob(File.join(pub_path, '**', '*.rb')).sort.each do |file|
            box.require(file)
          end
        end
      end
    end

    def wire_dependency_namespaces(box, package, package_resolver)
      package_resolver.direct_dependencies(package).each do |dep|
        dep_box = @boxes[dep.name]
        next unless dep_box

        # Check visibility: is dep visible to this package?
        unless VisibilityChecker.visible?(dep, package)
          next # Skip wiring — will raise NameError on access
        end

        # Check folder privacy
        unless FolderPrivacyChecker.accessible?(dep, package)
          next
        end

        # Check layer constraints
        if @layers.any?
          violation = LayerChecker.validate_dependency(package, dep, @layers)
          if violation
            raise LayerViolationError, violation
          end
        end

        namespace_name = PackageResolver.namespace_for(dep.name)
        next unless namespace_name

        # Build privacy constraints if enforce_privacy is enabled
        pub_consts = PrivacyChecker.public_constants(dep, @root_path)
        priv_consts = PrivacyChecker.enforces_privacy?(dep) ?
          PrivacyChecker.private_constants_list(dep, namespace: namespace_name) : nil

        proxy = ConstantResolver.create_namespace_proxy(
          dep_box,
          public_constants: pub_consts,
          private_constants: priv_consts,
          package_name: dep.name,
        )
        box.const_set(namespace_name.to_sym, proxy)
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

  class LayerViolationError < RuntimeError; end
end
