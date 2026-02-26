# frozen_string_literal: true

module Boxwerk
  # Command-line interface. Delegates to Setup for package boot.
  module CLI
    class << self
      def run(argv)
        if argv.empty?
          print_usage
          exit 1
        end

        case argv[0]
        when 'run'
          run_command(argv[1..])
        when 'console'
          console_command(argv[1..])
        when 'info'
          info_command
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
        puts "boxwerk #{Boxwerk::VERSION} — Runtime enforcement companion to Packwerk"
        puts ''
        puts 'Usage: boxwerk <command> [args...]'
        puts ''
        puts 'Commands:'
        puts '  run <script.rb> [args...]    Run a script in the root package context'
        puts '  console [irb-args...]        Start an IRB console in the root package context'
        puts '  info                         Show package structure and dependency graph'
        puts '  help                         Show this help message'
        puts '  version                      Show version'
        puts ''
        puts 'Requires: Ruby 4.0.1+ with RUBY_BOX=1 and Packwerk package.yml files'
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
        layers = LayerChecker.layers_for(File.expand_path('.'))

        puts "boxwerk #{Boxwerk::VERSION}"
        puts ''
        puts "Root: #{resolver.root.name}"
        puts "Packages: #{resolver.packages.size}"

        if layers.any?
          puts "Layers: #{layers.join(' > ')}"
        end

        puts ''
        resolver.topological_order.each do |pkg|
          flags = []
          flags << "layer: #{pkg.config['layer']}" if pkg.config['layer']
          flags << 'private' if pkg.config['enforce_privacy']
          flags << 'visible' if pkg.config['enforce_visibility']
          flags << 'folder_private' if pkg.config['enforce_folder_privacy']
          flags << 'layers' if pkg.config['enforce_layers'] || pkg.config['enforce_architecture']

          flag_str = flags.any? ? " [#{flags.join(', ')}]" : ''
          puts "  #{pkg.name}#{flag_str}"

          deps = pkg.dependencies
          if deps.any?
            puts "    dependencies: #{deps.join(', ')}"
          end

          visible_to = pkg.config['visible_to']
          if visible_to
            puts "    visible_to: #{visible_to.join(', ')}"
          end
        end
      end

      def perform_setup
        Boxwerk::Setup.run!(start_dir: Dir.pwd)
      rescue => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      def execute_in_box(box, script_path, script_args)
        box.eval("ARGV.replace(#{script_args.inspect})")
        box.require(File.expand_path(script_path))
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
