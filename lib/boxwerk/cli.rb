# frozen_string_literal: true

module Boxwerk
  # Command-line interface. Delegates to Setup for package boot.
  #
  # Primary commands:
  #   exec — run any Ruby command (gem binstub) in the boxed environment
  #   run  — shorthand for running a Ruby script in the root box
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
        puts 'Usage: boxwerk <command> [args...]'
        puts ''
        puts 'Commands:'
        puts '  exec <command> [args...]     Execute a Ruby command in the boxed environment'
        puts '  run <script.rb> [args...]    Run a Ruby script in the root box'
        puts '  console [irb-args...]        Start an IRB console in the root box'
        puts '  info                         Show package structure and dependencies'
        puts '  install                      Run bundle install in all packs with a gems.rb'
        puts '  help                         Show this help message'
        puts '  version                      Show version'
        puts ''
        puts 'Examples:'
        puts '  boxwerk run app.rb'
        puts '  boxwerk exec rake test'
        puts '  boxwerk exec rails console'
        puts '  boxwerk console'
        puts ''
        puts 'Setup:'
        puts '  bundle install                  Install global gems'
        puts '  bundle binstub boxwerk          Create bin/boxwerk binstub'
        puts '  bin/boxwerk install             Install gems for all packs'
        puts ''
        puts 'Requires: Ruby 4.0+ with Ruby::Box support and package.yml files'
      end

      # Execute a Ruby command (gem binstub) in the boxed environment.
      # Finds the command via Gem.bin_path and loads it in the root box.
      def exec_command(args)
        if args.empty?
          $stderr.puts 'Error: No command specified'
          $stderr.puts ''
          $stderr.puts 'Usage: boxwerk exec <command> [args...]'
          exit 1
        end

        command = args[0]
        command_args = args[1..] || []

        result = perform_setup
        root_box = result[:box_manager].boxes[result[:resolver].root.name]

        # If it looks like a Ruby script, load it directly
        if command.end_with?('.rb') || File.exist?(command)
          execute_in_box(root_box, command, command_args)
          return
        end

        # Find the gem binstub
        bin_path = find_bin_path(command)
        unless bin_path
          $stderr.puts "Error: Command not found: #{command}"
          $stderr.puts "Make sure '#{command}' is installed as a gem and available via Bundler."
          exit 1
        end

        # Gem binstubs are scripts, not libraries — use load instead of require
        execute_in_box(root_box, bin_path, command_args, use_load: true)
      end

      def run_command(args)
        if args.empty?
          $stderr.puts 'Error: No script specified'
          $stderr.puts ''
          $stderr.puts 'Usage: boxwerk run <script.rb> [args...]'
          exit 1
        end

        script_path = args[0]
        unless File.exist?(script_path)
          $stderr.puts "Error: Script not found: #{script_path}"
          exit 1
        end

        result = perform_setup
        root_box = result[:box_manager].boxes[result[:resolver].root.name]
        execute_in_box(root_box, script_path, args[1..] || [])
      end

      def console_command(args)
        require 'irb'
        result = perform_setup
        root_box = result[:box_manager].boxes[result[:resolver].root.name]
        start_console_in_box(root_box, args)
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

          puts "Installing gems for #{pkg.name}..."
          Dir.chdir(pkg_dir) do
            success = system({ 'BUNDLE_GEMFILE' => File.join(pkg_dir, gemfile) },
                             'bundle', 'install', '--quiet')
            unless success
              $stderr.puts "  Error: bundle install failed in #{pkg.name}"
              exit 1
            end
          end
          installed += 1
        end

        if installed == 0
          puts 'No packs with Gemfiles found.'
        else
          puts "Installed gems for #{installed} pack#{'s' unless installed == 1}."
        end
      end

      def perform_setup
        Boxwerk::Setup.run!(start_dir: Dir.pwd)
      rescue => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      def execute_in_box(box, script_path, script_args, use_load: false)
        expanded = File.expand_path(script_path)
        box.eval("ARGV.replace(#{script_args.inspect})")
        if use_load
          box.eval("load #{expanded.inspect}")
        else
          box.require(expanded)
        end
      end

      # Resolves a command name to its gem binstub path.
      def find_bin_path(command)
        Gem.bin_path(command, command)
      rescue Gem::GemNotFoundException
        # Try finding it as a different gem's executable
        Gem::Specification.each do |spec|
          spec.executables.each do |exe|
            return spec.bin_file(exe) if exe == command
          end
        end
        nil
      end

      def start_console_in_box(box, irb_args = [])
        puts "boxwerk #{Boxwerk::VERSION} console"
        puts ''
        puts 'All packages loaded and wired. You are in the root package context.'
        puts 'Type "exit" or press Ctrl+D to quit.'
        puts ''

        box.eval(<<~RUBY)
          ARGV.replace(#{(['--noautocomplete'] + irb_args).inspect})
          IRB.start
        RUBY
      end
    end
  end
end
