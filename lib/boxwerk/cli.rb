# frozen_string_literal: true

module Boxwerk
  # Command-line interface. Delegates to Setup for package boot.
  #
  # Primary commands:
  #   exec    — run any Ruby command (gem binstub) in the boxed environment
  #   run     — run a Ruby script in a package box
  #   console — start an IRB console in a package box
  module CLI
    class << self
      def run(argv)
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
        puts '  -p, --package <name>         Run in a specific package box (default: root)'
        puts '      --all                    Run command for all packages sequentially'
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
        puts '  gem install boxwerk             Install boxwerk'
        puts '  boxwerk install                 Install gems for all packages'
        puts ''
        puts 'Requires: Ruby 4.0+ with RUBY_BOX=1 and package.yml files'
      end

      # Parses --package/-p and --all flags from args, returning
      # { package: name_or_nil, all: bool, remaining: [...] }.
      def parse_package_flag(args)
        package_name = nil
        all = false
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
          else
            # Once we hit a non-flag, the rest are the command/args
            remaining = args[i..]
            break
          end
        end

        { package: package_name, all: all, remaining: remaining }
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

        # Install the root package's dependency resolver on Ruby::Box.root.
        # Gems loaded via Bundler.require run in the root box (where their
        # methods were defined). When those gems call load() (e.g. rake
        # loading a Rakefile), the loaded files execute in the root box too.
        # Without this, const_missing wouldn't fire for package constants.
        install_resolver_on_ruby_root(result)

        if parsed[:all]
          # Run command for all packages sequentially
          result[:resolver].topological_order.each do |pkg|
            box = result[:box_manager].boxes[pkg.name]
            next unless box

            label = pkg.root? ? '.' : pkg.name
            puts "==> #{label}"
            run_command_in_box(result, box, command, command_args)
            puts ''
          end
        else
          box = resolve_target_box(result, parsed[:package])
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
        box = resolve_target_box(result, parsed[:package])
        install_resolver_on_ruby_root(result)
        execute_in_box(box, script_path, parsed[:remaining][1..] || [])
      end

      def console_command(args)
        require 'irb'
        parsed = parse_package_flag(args)

        result = perform_setup
        box = resolve_target_box(result, parsed[:package])
        install_resolver_on_ruby_root(result)

        pkg_label = parsed[:package] || 'root'
        start_console_in_box(box, parsed[:remaining], pkg_label)
      end

      def info_command
        result = perform_setup
        resolver = result[:resolver]

        puts "boxwerk #{Boxwerk::VERSION}"
        puts ''
        puts "Root: #{resolver.root.name}"
        puts "Packages: #{resolver.packages.size}"

        puts ''
        resolver.topological_order.each do |pkg|
          flags = []
          flags << 'private' if pkg.config['enforce_privacy']

          flag_str = flags.any? ? " [#{flags.join(', ')}]" : ''
          puts "  #{pkg.name}#{flag_str}"

          deps = pkg.dependencies
          if deps.any?
            puts "    dependencies: #{deps.join(', ')}"
          end
        end
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

      # Installs the root package's dependency resolver on Ruby::Box.root.
      # Gems are loaded into Ruby::Box.root via Bundler.require, so their
      # methods execute in the root box context. When those gem methods call
      # load() (e.g. rake loading a Rakefile), the loaded files also run in
      # the root box. This method ensures const_missing is available there
      # so that package constants can be resolved.
      def install_resolver_on_ruby_root(result)
        root_pkg = result[:resolver].root
        root_box = result[:box_manager].boxes[root_pkg.name]
        resolver_const = root_box.const_get(:BOXWERK_DEPENDENCY_RESOLVER)
        return unless resolver_const

        ruby_root = Ruby::Box.root
        ruby_root.send(:remove_const, :BOXWERK_DEPENDENCY_RESOLVER) if ruby_root.const_defined?(:BOXWERK_DEPENDENCY_RESOLVER)
        ruby_root.const_set(:BOXWERK_DEPENDENCY_RESOLVER, resolver_const)
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

      def start_console_in_box(box, irb_args = [], pkg_label = 'root')
        puts "boxwerk #{Boxwerk::VERSION} console (#{pkg_label})"
        puts ''
        puts 'All packages loaded and wired. Type "exit" or press Ctrl+D to quit.'
        puts ''

        box.eval(<<~RUBY)
          ARGV.replace(#{(['--noautocomplete'] + irb_args).inspect})
          IRB.start
        RUBY
      end
    end
  end
end
