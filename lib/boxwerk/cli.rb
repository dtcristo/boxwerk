# frozen_string_literal: true

require 'rbconfig'

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
        puts '  info                         Show package structure and dependencies'
        puts '  install                      Install gems for all packages'
        puts '  help                         Show this help message'
        puts '  version                      Show version'
        puts ''
        puts 'Options:'
        puts '  -p, --package <name>         Run in a specific package box (default: .)'
        puts '      --all                    Run exec for all packages sequentially'
        puts '  -r, --root-box               Run in the root box (no package context)'
        puts ''
        puts 'Examples:'
        puts '  boxwerk run app.rb'
        puts '  boxwerk exec rake test'
        puts '  boxwerk exec -p packs/util rake test'
        puts '  boxwerk exec --all rake test'
        puts '  boxwerk console'
        puts '  boxwerk console -p packs/finance'
        puts ''
        puts 'Setup:'
        puts '  # Add gem \'boxwerk\' to your Gemfile, then:'
        puts '  bundle install                       Install gems (including boxwerk)'
        puts '  bundle binstubs boxwerk              Create bin/boxwerk binstub'
        puts '  bin/boxwerk install                  Install per-package gems'
        puts '  RUBY_BOX=1 bin/boxwerk run app.rb    Run your app'
        puts ''
        puts 'Requires: Ruby 4.0+ with RUBY_BOX=1 for exec/run/console commands'
      end

      # Parses --package/-p, --all, and --root-box/-r flags from args, returning
      # { package: name_or_nil, all: bool, root_box: bool, remaining: [...] }.
      def parse_package_flag(args)
        package_name = nil
        all = false
        root_box = false
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
          when '--all'
            all = true
            i += 1
          when '--root-box', '-r'
            root_box = true
            i += 1
          else
            remaining = args[i..]
            break
          end
        end

        { package: package_name, all: all, root_box: root_box, remaining: remaining }
      end

      # Resolves the target box for a command given parsed flags.
      def resolve_target_box(result, package_name)
        if package_name
          box = result[:box_manager].boxes[package_name]
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

        result = perform_setup

        if parsed[:all]
          # Run command for each package in a separate subprocess to
          # ensure clean isolation (avoids at_exit conflicts from test
          # frameworks like minitest registering tests globally).
          root_path = Setup.send(:find_root, Dir.pwd)
          failed = []

          result[:resolver].topological_order.each do |pkg|
            label = pkg.root? ? '.' : pkg.name
            pkg_name = pkg.root? ? '.' : pkg.name
            puts "==> #{label}"
            # Clear BUNDLE_GEMFILE so the subprocess discovers it fresh
            env = { 'RUBY_BOX' => '1', 'BUNDLE_GEMFILE' => nil }
            success = system(
              env,
              RbConfig.ruby, @exe_path, 'exec', '-p', pkg_name, command, *command_args,
              chdir: root_path
            )
            failed << label unless success
            puts ''
          end

          unless failed.empty?
            $stderr.puts "Failed in: #{failed.join(', ')}"
            exit 1
          end
        else
          if parsed[:root_box]
            box = Ruby::Box.root
          else
            target_pkg = parsed[:package] ? result[:resolver].packages[parsed[:package]] : nil
            box = resolve_target_box(result, parsed[:package])
            install_resolver_on_ruby_root(result, target_package: target_pkg)

            if parsed[:package] && parsed[:package] != '.'
              root_path = Setup.send(:find_root, Dir.pwd)
              pkg_dir = File.join(root_path, parsed[:package])
              Dir.chdir(pkg_dir)
            end
          end
          run_command_in_box(result, box, command, command_args)
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

        result = perform_setup
        if parsed[:root_box]
          box = Ruby::Box.root
        else
          target_pkg = parsed[:package] ? result[:resolver].packages[parsed[:package]] : nil
          box = resolve_target_box(result, parsed[:package])
          install_resolver_on_ruby_root(result, target_package: target_pkg)
        end
        execute_in_box(box, script_path, parsed[:remaining][1..] || [])
      end

      def console_command(args)
        parsed = parse_package_flag(args)

        result = perform_setup
        if parsed[:root_box]
          pkg_label = 'root box'
        else
          target_pkg = parsed[:package] ? result[:resolver].packages[parsed[:package]] : nil
          install_resolver_on_ruby_root(result, target_package: target_pkg)
          pkg_label = parsed[:package] || '.'
        end
        # IRB runs in Ruby::Box.root with a composite resolver that provides
        # the target package's constants. This works around a Ruby 4.0.1 GC
        # crash when running IRB directly in child boxes.
        start_console_in_box(Ruby::Box.root, parsed[:remaining], pkg_label)
      end

      def info_command
        root_path = Setup.send(:find_root, Dir.pwd)
        unless root_path
          $stderr.puts 'Error: Cannot find package.yml in current directory or ancestors'
          exit 1
        end

        resolver = PackageResolver.new(root_path)

        puts "boxwerk #{Boxwerk::VERSION}"
        puts ''
        puts 'Dependency Graph'
        puts ''
        print_dependency_tree(resolver)
        puts ''
        puts 'Packages'
        puts ''
        print_package_details(resolver, root_path)
      end

      def install_command
        root_path = Setup.send(:find_root, Dir.pwd)
        unless root_path
          $stderr.puts 'Error: Cannot find package.yml in current directory or ancestors'
          exit 1
        end

        resolver = PackageResolver.new(root_path)
        installed = 0

        resolver.topological_order.each do |pkg|
          pkg_dir = pkg.root? ? root_path : File.join(root_path, pkg.name)
          gemfile = %w[gems.rb Gemfile].find { |f| File.exist?(File.join(pkg_dir, f)) }
          next unless gemfile

          label = pkg.root? ? '.' : pkg.name
          puts "Installing gems for #{label}..."
          Dir.chdir(pkg_dir) do
            success = system('bundle', 'install', '--quiet')
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

      def perform_setup
        Boxwerk::Setup.run!(start_dir: Dir.pwd)
      rescue => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      # Runs a command (binstub or script) in a box.
      def run_command_in_box(result, box, command, command_args)
        if command.end_with?('.rb') || File.exist?(command)
          execute_in_box(box, command, command_args)
        else
          bin_path = find_bin_path(command)
          unless bin_path
            $stderr.puts "Error: Command not found: #{command}"
            $stderr.puts "Make sure '#{command}' is installed as a gem."
            exit 1
          end
          execute_in_box(box, bin_path, command_args, use_load: true)
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
          box.require(expanded)
        end
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

        # Build a composite resolver: first check the target box's own
        # constants, then fall through to the target box's dependency resolver.
        own_box = target_box
        dep_resolver = begin
          target_box.const_get(:BOXWERK_DEPENDENCY_RESOLVER)
        rescue NameError
          nil
        end

        composite = proc do |const_name|
          name_str = const_name.to_s
          # Try own box first (for the pack's internal constants).
          # Use eval to trigger autoload within the box's context.
          begin
            own_box.eval("_ = ::#{name_str}")
          rescue NameError
            # Fall through to dependency resolver
            if dep_resolver
              dep_resolver.call(const_name)
            else
              raise NameError, "uninitialized constant #{name_str}"
            end
          end
        end

        ruby_root = Ruby::Box.root
        ruby_root.send(:remove_const, :BOXWERK_DEPENDENCY_RESOLVER) if ruby_root.const_defined?(:BOXWERK_DEPENDENCY_RESOLVER)
        ruby_root.const_set(:BOXWERK_DEPENDENCY_RESOLVER, composite)
        ruby_root.eval(<<~RUBY)
          class Object
            def self.const_missing(const_name)
              BOXWERK_DEPENDENCY_RESOLVER.call(const_name)
            end
          end
        RUBY
      end

      # Resolves a command name to its gem binstub path.
      def find_bin_path(command)
        Gem.bin_path(command, command)
      rescue Gem::GemNotFoundException
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

      def print_tree_children(dep_names, resolver, prefix)
        dep_names.each_with_index do |dep_name, i|
          last = (i == dep_names.length - 1)
          connector = last ? '└── ' : '├── '
          puts "#{prefix}#{connector}#{dep_name}"

          pkg = resolver.packages[dep_name]
          if pkg && pkg.dependencies.any?
            child_prefix = prefix + (last ? '    ' : '│   ')
            print_tree_children(pkg.dependencies, resolver, child_prefix)
          end
        end
      end

      def print_package_details(resolver, root_path)
        resolver.topological_order.each do |pkg|
          label = pkg.root? ? '.' : pkg.name
          puts "  #{label}"

          flags = []
          flags << 'enforce_dependencies' if pkg.enforce_dependencies?
          flags << 'enforce_privacy' if pkg.config['enforce_privacy']
          puts "    enforcements: #{flags.any? ? flags.join(', ') : 'none'}"

          deps = pkg.dependencies
          puts "    dependencies: #{deps.any? ? deps.join(', ') : 'none'}"

          pkg_dir = pkg.root? ? root_path : File.join(root_path, pkg.name)
          gemfile = %w[gems.rb Gemfile].find { |f| File.exist?(File.join(pkg_dir, f)) }
          puts "    gems: #{gemfile || 'none'}" if !pkg.root? && gemfile

          if pkg.config['enforce_privacy']
            public_path = pkg.config['public_path'] || 'public/'
            puts "    public_path: #{public_path}"
          end

          puts ''
        end
      end
    end
  end
end
