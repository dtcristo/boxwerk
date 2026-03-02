# frozen_string_literal: true

require 'rbconfig'
require 'stringio'

module Boxwerk
  # Command-line interface. Delegates to Setup for package boot.
  #
  # Primary commands:
  #   exec    — run any Ruby command (gem binstub) in the boxed environment
  #   run     — run a Ruby script in a package box
  #   console — start an IRB console in a package box
  module CLI
    class << self
      attr_accessor :exe_path

      def run(argv, exe_path: nil)
        @exe_path = exe_path
        if argv.empty?
          print_usage
          exit 1
        end

        case argv[0]
        when 'exec'
          exec_command(argv[1..])
        when 'run'
          run_command(argv[1..])
        when 'console'
          console_command(argv[1..])
        when 'info'
          info_command
        when 'install'
          install_command
        when 'help', '--help', '-h'
          print_usage
          exit 0
        when 'version', '--version', '-v'
          puts "boxwerk #{Boxwerk::VERSION}"
          exit 0
        else
          $stderr.puts "Error: Unknown command '#{argv[0]}'"
          $stderr.puts ''
          print_usage
          exit 1
        end
      end

      private

      def print_usage
        puts "boxwerk #{Boxwerk::VERSION} — Runtime package isolation for Ruby"
        puts ''
        puts 'Usage: boxwerk <command> [options] [args...]'
        puts ''
        puts 'Commands:'
        puts '  exec <command> [args...]     Execute a command in the boxed environment'
        puts '  run <script.rb> [args...]    Run a Ruby script in a package box'
        puts '  console [irb-args...]        Start an IRB console in a package box'
        puts '  RUBY_BOX=1 info              Boot and show runtime autoload structure'
        puts '  install                      Install gems for all packages'
        puts '  help                         Show this help message'
        puts '  version                      Show version'
        puts ''
        puts 'Options:'
        puts '  -p, --package <name>         Run in a specific package box (default: .)'
        puts '  -a, --all                    Run exec for all packages sequentially'
        puts '  -g, --global                 Run in the global context (no package)'
        puts '      --package-paths <paths>  Comma-separated package path globs'
        puts '      --[no-]eager-load-global Toggle global eager loading'
        puts '      --[no-]eager-load-packages Toggle package eager loading'
        puts ''
        puts 'Examples:'
        puts '  boxwerk run main.rb'
        puts '  boxwerk exec rake test'
        puts '  boxwerk exec --package packs/util rake test'
        puts '  boxwerk exec --all rake test'
        puts '  boxwerk console'
        puts '  boxwerk console --global'
        puts ''
        puts 'Setup:'
        puts '  gem install boxwerk                  Install boxwerk'
        puts '  RUBY_BOX=1 boxwerk run main.rb       Run your app'
        puts ''
        puts '  # Or with Bundler:'
        puts '  bundle install                       Install gems (including boxwerk)'
        puts '  bundle binstubs boxwerk              Create bin/boxwerk binstub'
        puts '  RUBY_BOX=1 bin/boxwerk run main.rb   Run your app'
        puts ''
        puts 'Requires: Ruby 4.0+ with RUBY_BOX=1 for exec/run/console commands'
      end

      # Parses --package/-p, --all, and --global/-g flags from args, returning
      # { package: name_or_nil, all: bool, global: bool, remaining: [...] }.
      def parse_package_flag(args)
        package_name = nil
        all = false
        global = false
        config = {}
        remaining = []
        i = 0

        while i < args.length
          case args[i]
          when '--package', '-p'
            package_name = args[i + 1]
            unless package_name
              $stderr.puts 'Error: --package requires a package name'
              exit 1
            end
            i += 2
          when '--all', '-a'
            all = true
            i += 1
          when '--global', '-g'
            global = true
            i += 1
          when '--package-paths'
            value = args[i + 1]
            unless value
              $stderr.puts 'Error: --package-paths requires a value'
              exit 1
            end
            config['package_paths'] = value.split(',').map(&:strip)
            i += 2
          when '--eager-load-global'
            config['eager_load_global'] = true
            i += 1
          when '--no-eager-load-global'
            config['eager_load_global'] = false
            i += 1
          when '--eager-load-packages'
            config['eager_load_packages'] = true
            i += 1
          when '--no-eager-load-packages'
            config['eager_load_packages'] = false
            i += 1
          else
            remaining = args[i..]
            break
          end
        end

        {
          package: package_name,
          all: all,
          global: global,
          config: config,
          remaining: remaining,
        }
      end

      # Resolves the target box for a command given parsed flags.
      def resolve_target_box(result, package_name)
        if package_name
          normalized = Package.normalize(package_name)
          box = result[:box_manager].boxes[normalized]
          unless box
            $stderr.puts "Error: Unknown package '#{package_name}'"
            $stderr.puts "Available packages: #{result[:resolver].packages.keys.join(', ')}"
            exit 1
          end
          box
        else
          result[:box_manager].boxes[result[:resolver].root.name]
        end
      end

      # Execute a Ruby command (gem binstub) in the boxed environment.
      def exec_command(args)
        parsed = parse_package_flag(args)

        if parsed[:remaining].empty?
          $stderr.puts 'Error: No command specified'
          $stderr.puts ''
          $stderr.puts 'Usage: boxwerk exec [-p <package>] <command> [args...]'
          exit 1
        end

        command = parsed[:remaining][0]
        command_args = parsed[:remaining][1..] || []

        if parsed[:all]
          # Boot all for --all (each subprocess boots its own target)
          result = perform_setup
          root_path = Setup.send(:find_root, Dir.pwd)
          failed = []

          result[:resolver].topological_order.each do |pkg|
            label = pkg.root? ? '.' : pkg.name
            pkg_name = pkg.root? ? '.' : pkg.name
            puts "==> #{label}"
            env = { 'RUBY_BOX' => '1', 'BUNDLE_GEMFILE' => nil }
            success =
              system(
                env,
                RbConfig.ruby,
                @exe_path,
                'exec',
                '-p',
                pkg_name,
                command,
                *command_args,
                chdir: root_path,
              )
            failed << label unless success
            puts ''
          end

          unless failed.empty?
            $stderr.puts "Failed in: #{failed.join(', ')}"
            exit 1
          end
        else
          # Selective boot: only target + deps (global boots all)
          target_packages = resolve_boot_targets(parsed)
          result =
            perform_setup(packages: target_packages, config: parsed[:config])

          if parsed[:global]
            box = Ruby::Box.root
            install_global_resolver(result)
          else
            target_pkg =
              (
                if parsed[:package]
                  result[:resolver].packages[parsed[:package]]
                else
                  nil
                end
              )
            box = resolve_target_box(result, parsed[:package])
            install_resolver_on_ruby_root(result, target_package: target_pkg)

            if parsed[:package] && parsed[:package] != '.'
              root_path = Setup.send(:find_root, Dir.pwd)
              pkg_dir = File.join(root_path, parsed[:package])
              Dir.chdir(pkg_dir)
            end
          end
          run_command_in_box(
            result,
            box,
            command,
            command_args,
            pkg_dir: Dir.pwd,
          )
        end
      end

      def run_command(args)
        parsed = parse_package_flag(args)

        if parsed[:remaining].empty?
          $stderr.puts 'Error: No script specified'
          $stderr.puts ''
          $stderr.puts 'Usage: boxwerk run [-p <package>] <script.rb> [args...]'
          exit 1
        end

        script_path = parsed[:remaining][0]
        unless File.exist?(script_path)
          $stderr.puts "Error: Script not found: #{script_path}"
          exit 1
        end

        target_packages = resolve_boot_targets(parsed)
        result =
          perform_setup(packages: target_packages, config: parsed[:config])
        if parsed[:global]
          box = Ruby::Box.root
          install_global_resolver(result)
        else
          target_pkg =
            (
              if parsed[:package]
                result[:resolver].packages[parsed[:package]]
              else
                nil
              end
            )
          box = resolve_target_box(result, parsed[:package])
          install_resolver_on_ruby_root(result, target_package: target_pkg)
        end
        execute_in_box(box, script_path, parsed[:remaining][1..] || [])
      end

      def console_command(args)
        parsed = parse_package_flag(args)

        target_packages = resolve_boot_targets(parsed)
        result =
          perform_setup(packages: target_packages, config: parsed[:config])
        if parsed[:global]
          install_global_resolver(result)
          pkg_label = 'global'
        else
          target_pkg =
            (
              if parsed[:package]
                result[:resolver].packages[parsed[:package]]
              else
                nil
              end
            )
          install_resolver_on_ruby_root(result, target_package: target_pkg)
          pkg_label = parsed[:package] || '.'
        end
        # IRB runs in Ruby::Box.root with a composite resolver that provides
        # the target package's constants. This works around a Ruby 4.0.1 GC
        # crash when running IRB directly in child boxes.
        start_console_in_box(Ruby::Box.root, parsed[:remaining], pkg_label)
      end

      BOXWERK_CONFIG_DEFAULTS = {
        'package_paths' => ['**/'],
        'eager_load_global' => true,
        'eager_load_packages' => false,
      }.freeze

      def info_command
        # Boot the application, suppressing stdout from boot scripts
        result = nil
        orig_stdout = $stdout
        $stdout = StringIO.new
        begin
          result = perform_setup
        ensure
          $stdout = orig_stdout
        end

        root_path = result[:root_path]
        resolver = result[:resolver]
        box_manager = result[:box_manager]
        config = BOXWERK_CONFIG_DEFAULTS.merge(resolver.boxwerk_config)
        eager_global = config.fetch('eager_load_global', true)
        eager_packages = config.fetch('eager_load_packages', false)
        gem_resolver = GemResolver.new(root_path)

        puts "boxwerk #{Boxwerk::VERSION}"
        puts ''

        # Config — always shown with defaults filled in
        puts 'Config'
        puts ''
        config.each { |k, v| puts "  #{k}: #{v.inspect}" }
        puts ''

        # Dependency Graph
        puts 'Dependency Graph'
        puts ''
        print_dependency_tree(resolver)
        puts ''

        # Global section
        global = Boxwerk.global
        global_boot = File.join(root_path, 'global', 'boot.rb')
        global_autoload_dirs =
          (global&.default_dirs || []) +
            (global&.autoloader&.autoload_dirs || []).map do |d|
              normalize_dir_display(d, root_path)
            end
        global_collapse_dirs =
          (global&.autoloader&.collapse_dirs || []).map do |d|
            normalize_dir_display(d, root_path)
          end
        global_ignore_dirs =
          (global&.autoloader&.ignore_dirs || []).map do |d|
            normalize_dir_display(d, root_path)
          end
        root_gems =
          gem_resolver.gems_for(resolver.root)&.select { |g| !g.autorequire.nil? }
        global_has_content =
          File.exist?(global_boot) || global_autoload_dirs.any? || root_gems&.any?

        if global_has_content
          puts 'Global'
          puts ''
          puts "  boot: global/boot.rb" if File.exist?(global_boot)
          if global_autoload_dirs.any?
            puts '  autoload_dirs:'
            global_autoload_dirs.each do |dir|
              suffix = eager_global ? ' (eager)' : ''
              puts "    #{dir}#{suffix}"
            end
          end
          if global_collapse_dirs.any?
            puts '  collapse_dirs:'
            global_collapse_dirs.each { |dir| puts "    #{dir}" }
          end
          if global_ignore_dirs.any?
            puts '  ignore_dirs:'
            global_ignore_dirs.each { |dir| puts "    #{dir}" }
          end
          if root_gems&.any?
            puts '  gems:'
            root_gems.each { |g| puts "    #{g.name} (#{g.version})" }
          end
          puts ''
        end

        # Packages — root (.) first, then others
        puts 'Packages'
        puts ''
        root_first = [resolver.root] + resolver.topological_order.reject(&:root?)
        root_first.each do |pkg|
          print_package_info(pkg, box_manager, gem_resolver, root_path, eager_packages)
        end

        # Gem conflicts
        conflicts = gem_resolver.check_conflicts(resolver)
        if conflicts.any?
          puts 'Gem Conflicts'
          puts ''
          conflicts.each do |c|
            puts "  ⚠ #{c[:gem_name]}: #{c[:package_version]} in #{c[:package]} " \
                   "vs #{c[:global_version]} in root (both loaded into memory)"
          end
          puts ''
        end
      end

      def install_command
        root_path = Setup.send(:find_root, Dir.pwd)

        resolver = PackageResolver.new(root_path)
        installed = 0

        resolver.topological_order.each do |pkg|
          pkg_dir = pkg.root? ? root_path : File.join(root_path, pkg.name)
          gemfile =
            %w[gems.rb Gemfile].find { |f| File.exist?(File.join(pkg_dir, f)) }
          next unless gemfile

          label = pkg.root? ? '.' : pkg.name
          puts "Installing gems for #{label}..."
          Dir.chdir(pkg_dir) do
            # Clear Bundler env vars so each package uses its own Gemfile,
            # not the parent process's BUNDLE_GEMFILE or BUNDLE_PATH.
            success =
              Bundler.with_unbundled_env do
                system('bundle', 'install', '--retry', '3', '--quiet')
              end
            unless success
              $stderr.puts "  Error: bundle install failed in #{label}"
              exit 1
            end
          end
          installed += 1
        end

        if installed == 0
          puts 'No packages with a Gemfile or gems.rb found.'
        else
          puts "Installed gems for #{installed} package#{'s' unless installed == 1}."
        end
      end

      # Determines which packages to boot based on parsed flags.
      # Returns nil for --all or --global (boot all), or an array
      # of target Package objects for selective booting.
      def resolve_boot_targets(parsed)
        return nil if parsed[:all] || parsed[:global]

        # For a specific package, resolve it from package.yml discovery
        # to get the Package object. Setup.run will boot it + deps.
        if parsed[:package]
          root_path = Setup.send(:find_root, Dir.pwd)
          resolver = PackageResolver.new(root_path)
          normalized = Package.normalize(parsed[:package])
          pkg = resolver.packages[normalized]
          unless pkg
            $stderr.puts "Error: Unknown package '#{parsed[:package]}'"
            $stderr.puts "Available packages: #{resolver.packages.keys.join(', ')}"
            exit 1
          end
          [pkg]
        else
          # Default: boot root package + deps
          nil
        end
      end

      def perform_setup(packages: nil, config: {})
        Boxwerk::Setup.run(
          start_dir: Dir.pwd,
          packages: packages,
          config: config,
        )
      rescue => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      # Runs a command (binstub or script) in a box.
      # Falls back to running as a shell command in pkg_dir if no
      # binstub or gem binary is found.
      def run_command_in_box(result, box, command, command_args, pkg_dir: nil)
        if command.end_with?('.rb') || File.exist?(command)
          execute_in_box(box, command, command_args)
        else
          # Check for project-level bin/<command> first, then gem binstubs
          project_bin = File.join(Dir.pwd, 'bin', command)
          if File.exist?(project_bin)
            execute_in_box(box, project_bin, command_args)
          else
            bin_path = find_bin_path(command)
            if bin_path
              execute_in_box(box, bin_path, command_args, use_load: true)
            else
              # Fall back to shell command in the package directory
              dir = pkg_dir || Dir.pwd
              success = system(command, *command_args, chdir: dir)
              exit(success ? 0 : 1)
            end
          end
        end
      end

      def execute_in_box(box, script_path, script_args, use_load: false)
        expanded = File.expand_path(script_path)
        box.eval("ARGV.replace(#{script_args.inspect})")
        if use_load
          # Eval file content directly rather than using load, because
          # load creates a new file scope where inherited DSL methods
          # (e.g. Rake's task) may not be visible in Ruby::Box.
          content = File.read(expanded)
          box.eval(content)
        else
          # Use eval with __dir__ set so relative paths resolve
          # correctly (e.g. project binstubs using File.expand_path).
          content = File.read(expanded)
          dir = File.dirname(expanded)
          wrapped = "__dir__ = #{dir.inspect}\n" + content
          box.eval(wrapped)
        end
      end

      # Installs a resolver on Ruby::Box.root that searches ALL packages.
      # Used for --global mode so the global context can resolve any constant.
      def install_global_resolver(result)
        boxes = result[:box_manager].boxes
        file_indexes = result[:box_manager].instance_variable_get(:@file_indexes)

        all_boxes =
          result[:resolver]
            .packages
            .values
            .filter_map do |pkg|
              box = boxes[pkg.name]
              next unless box
              { box: box, file_index: file_indexes[pkg.name] || {} }
            end

        composite =
          proc do |const_name|
            name_str = const_name.to_s
            found = false
            value = nil

            all_boxes.each do |entry|
              box = entry[:box]
              file_index = entry[:file_index]

              has_constant =
                file_index.key?(name_str) ||
                  file_index.any? { |k, _| k.start_with?("#{name_str}::") } ||
                  (
                    begin
                      box.const_get(const_name)
                      true
                    rescue NameError
                      false
                    end
                  )

              next unless has_constant

              value =
                begin
                  box.const_get(const_name)
                rescue NameError
                  file = file_index[name_str]
                  if file
                    box.require(file)
                    box.const_get(const_name)
                  else
                    child_key =
                      file_index.keys.find do |k|
                        k.start_with?("#{name_str}::")
                      end
                    if child_key
                      box.require(file_index[child_key])
                      box.const_get(const_name)
                    else
                      next
                    end
                  end
                end

              found = true
              break
            end

            unless found
              raise NameError.new(
                "uninitialized constant #{name_str}",
                const_name,
              )
            end
            value
          end

        ruby_root = Ruby::Box.root
        if ruby_root.const_defined?(:BOXWERK_DEPENDENCY_RESOLVER)
          ruby_root.send(:remove_const, :BOXWERK_DEPENDENCY_RESOLVER)
        end
        ruby_root.const_set(:BOXWERK_DEPENDENCY_RESOLVER, composite)
        ruby_root.eval(<<~RUBY)
          class Object
            def self.const_missing(const_name)
              BOXWERK_DEPENDENCY_RESOLVER.call(const_name)
            end
          end
        RUBY
      end

      # Installs a dependency resolver on Ruby::Box.root for the given
      # package. Gems loaded via Bundler.require run in the root box (where
      # their methods were defined). When those gems call load() (e.g. rake
      # loading a Rakefile), the loaded files execute in the root box too.
      # This method ensures const_missing is available there so that package
      # constants can be resolved.
      #
      # When target_package is specified, the resolver also searches the
      # target package's own box for its internal constants. This enables
      # per-package testing where test files (loaded by rake in Ruby::Box.root)
      # need access to the pack's own constants.
      def install_resolver_on_ruby_root(result, target_package: nil)
        target_pkg = target_package || result[:resolver].root
        target_box = result[:box_manager].boxes[target_pkg.name]

        # Delegate constant resolution from Ruby::Box.root to the target box.
        # The target box already has its own const_missing (dependency resolver)
        # for cross-package lookup. We check own constants first via
        # const_get (which doesn't trigger const_missing recursion), then
        # fall through to the dependency resolver.
        own_box = target_box
        dep_resolver =
          begin
            target_box.const_get(:BOXWERK_DEPENDENCY_RESOLVER)
          rescue NameError
            nil
          end

        # File index for the target package (for autoload-style loading)
        file_index = result[:box_manager].file_indexes[target_pkg.name] || {}

        composite =
          proc do |const_name|
            name_str = const_name.to_s
            # Try own box's already-defined constants first
            resolved =
              begin
                own_box.const_get(const_name)
              rescue NameError
                nil
              end

            if resolved
              resolved
            else
              # Try loading from file index (autoload entries)
              file = file_index[name_str]
              if file
                own_box.require(file)
                own_box.const_get(const_name)
              elsif dep_resolver
                # Delegate to the target box's dependency resolver
                dep_resolver.call(const_name)
              else
                raise NameError.new(
                        "uninitialized constant #{name_str}",
                        const_name,
                      )
              end
            end
          end

        ruby_root = Ruby::Box.root
        if ruby_root.const_defined?(:BOXWERK_DEPENDENCY_RESOLVER)
          ruby_root.send(:remove_const, :BOXWERK_DEPENDENCY_RESOLVER)
        end
        ruby_root.const_set(:BOXWERK_DEPENDENCY_RESOLVER, composite)
        ruby_root.eval(<<~RUBY)
          class Object
            def self.const_missing(const_name)
              BOXWERK_DEPENDENCY_RESOLVER.call(const_name)
            end
          end
        RUBY
      end

      # Resolves a command name to its gem executable path. Iterates gem
      # specs directly to avoid Bundler's Gem.bin_path hook which prints
      # warnings when the gem name doesn't match the executable name
      # (e.g. "rails" executable is in the "railties" gem).
      def find_bin_path(command)
        Gem::Specification.each do |spec|
          spec.executables.each do |exe|
            return spec.bin_file(exe) if exe == command
          end
        end
        nil
      end

      def start_console_in_box(box, irb_args = [], pkg_label = '.')
        puts "boxwerk #{Boxwerk::VERSION} console (#{pkg_label})"
        puts ''

        box.eval(<<~RUBY)
          require 'irb'
          ARGV.replace(#{(['--noautocomplete'] + irb_args).inspect})
          IRB.start
        RUBY
      end

      # Renders a dependency tree like:
      #   .
      #   ├── packs/finance
      #   │   └── packs/util
      #   └── packs/greeting
      def print_dependency_tree(resolver)
        root = resolver.root
        puts root.name
        print_tree_children(root.dependencies, resolver, '')
      end

      def print_tree_children(dep_names, resolver, prefix, ancestry = Set.new)
        dep_names.each_with_index do |dep_name, i|
          last = (i == dep_names.length - 1)
          connector = last ? '└── ' : '├── '

          if ancestry.include?(dep_name)
            puts "#{prefix}#{connector}#{dep_name} (circular)"
          else
            puts "#{prefix}#{connector}#{dep_name}"
            pkg = resolver.packages[dep_name]
            if pkg && pkg.dependencies.any?
              child_prefix = prefix + (last ? '    ' : '│   ')
              print_tree_children(
                pkg.dependencies,
                resolver,
                child_prefix,
                ancestry | [dep_name],
              )
            end
          end
        end
      end

      def print_package_info(pkg, box_manager, gem_resolver, root_path, eager_packages)
        label = pkg.root? ? '  .' : "  #{pkg.name}"
        puts label

        flags = []
        flags << 'dependencies' if pkg.enforce_dependencies?
        flags << 'privacy' if pkg.config['enforce_privacy']
        if flags.any?
          puts '    enforcements:'
          flags.each { |f| puts "      #{f}" }
        else
          puts '    enforcements: none'
        end

        deps = pkg.dependencies
        if deps.any?
          puts '    dependencies:'
          deps.each { |d| puts "      #{d}" }
        else
          puts '    dependencies: none'
        end

        pkg_dir = pkg.root? ? root_path : File.join(root_path, pkg.name)
        puts "    boot: boot.rb" if File.exist?(File.join(pkg_dir, 'boot.rb'))

        # Autoload dirs: default (lib/, public/) + user push_dirs from boot.rb
        box = box_manager.boxes[pkg.name]
        al = box&.const_get(:BOXWERK_PACKAGE)&.autoloader
        autoload_dirs = al&.autoload_dirs || []
        collapse_dirs = al&.collapse_dirs || []
        ignore_dirs = al&.ignore_dirs || []

        if autoload_dirs.any?
          puts '    autoload_dirs:'
          autoload_dirs.each do |d|
            suffix = eager_packages ? ' (eager)' : ''
            puts "      #{normalize_dir_display(d, pkg_dir)}#{suffix}"
          end
        end
        if collapse_dirs.any?
          puts '    collapse_dirs:'
          collapse_dirs.each { |d| puts "      #{normalize_dir_display(d, pkg_dir)}" }
        end
        if ignore_dirs.any?
          puts '    ignore_dirs:'
          ignore_dirs.each { |d| puts "      #{normalize_dir_display(d, pkg_dir)}" }
        end

        # pack_public sigil constants
        pack_public = PrivacyChecker.pack_public_constants(pkg, root_path)
        if pack_public&.any?
          puts "    pack_public: #{pack_public.sort.join(', ')}"
        end

        private_consts = PrivacyChecker.private_constants_list(pkg)
        if private_consts.any?
          puts "    private constants: #{private_consts.sort.join(', ')}"
        end

        # Direct gems — last; root gems shown in Global section
        unless pkg.root?
          gems = gem_resolver.gems_for(pkg)
          direct_gems = gems&.select { |g| !g.autorequire.nil? }
          if direct_gems&.any?
            puts '    gems:'
            direct_gems.each { |g| puts "      #{g.name} (#{g.version})" }
          end
        end

        puts ''
      end

      # Normalizes a dir path for display: relative to base if possible,
      # otherwise absolute. Always has a trailing slash.
      def normalize_dir_display(dir, base)
        expanded = File.expand_path(dir, base)
        rel =
          if expanded.start_with?("#{base}/")
            expanded.delete_prefix("#{base}/")
          else
            expanded
          end
        rel.end_with?('/') ? rel : "#{rel}/"
      end
    end
  end
end
