# frozen_string_literal: true

module Boxwerk
  # CLI handles command-line execution of Boxwerk applications
  module CLI
    class << self
      # Main entry point for CLI
      # @param argv [Array<String>] Command line arguments
      def run(argv)
        if argv.empty?
          print_usage
          exit 1
        end

        command = argv[0]

        case command
        when 'run'
          run_command(argv[1..-1])
        when 'console'
          console_command(argv[1..-1])
        when 'help', '--help', '-h'
          print_usage
          exit 0
        else
          puts "Error: Unknown command '#{command}'"
          puts ''
          print_usage
          exit 1
        end
      end

      private

      def print_usage
        puts 'Boxwerk - Strict modularity runtime for Ruby'
        puts ''
        puts 'Usage: boxwerk <command> [args...]'
        puts ''
        puts 'Commands:'
        puts '  run <script.rb> [args...]    Run a script in the root package context'
        puts '  console [irb-args...]        Start an IRB console in the root package context'
        puts '  help                         Show this help message'
        puts ''
        puts 'All packages are loaded and wired before the command executes.'
      end

      def run_command(args)
        if args.empty?
          puts 'Error: No script specified'
          puts ''
          puts 'Usage: boxwerk run <script.rb> [args...]'
          exit 1
        end

        script_path = args[0]
        script_args = args[1..-1] || []

        # Verify script exists
        unless File.exist?(script_path)
          puts "Error: Script not found: #{script_path}"
          exit 1
        end

        # Perform Boxwerk setup (find package.yml, build graph, boot packages)
        graph = perform_setup

        # Execute the script in the root package's box
        root_package = graph.root
        execute_in_box(root_package.box, script_path, script_args)
      end

      def console_command(args)
        # Require IRB while we're still in root box context
        require 'irb'

        # Perform Boxwerk setup
        graph = perform_setup

        # Start IRB in the root package's box with provided args
        root_package = graph.root
        start_console_in_box(root_package.box, args)
      end

      def perform_setup
        begin
          Boxwerk::Setup.run!(start_dir: Dir.pwd)
        rescue => e
          puts "Error: #{e.message}"
          exit 1
        end
      end

      def execute_in_box(box, script_path, script_args)
        # Set ARGV for the script using eval
        box.eval("ARGV.replace(#{script_args.inspect})")

        # Run the script in the isolated box
        absolute_script_path = File.expand_path(script_path)
        box.require(absolute_script_path)
      end

      def start_console_in_box(box, irb_args = [])
        puts '=' * 70
        puts 'Boxwerk Console'
        puts '=' * 70
        puts ''
        puts 'All packages have been loaded and wired.'
        puts 'You are in the root package context.'
        puts ''
        puts 'Type "exit" or press Ctrl+D to quit.'
        puts '=' * 70
        puts ''

        # Start IRB in the box context.
        # TODO: This is currently broken. IRB runs the in the root box context.
        # This should be fixed by calling `require 'irb'` inside the box, but
        # that currently crashes the VM.
        # Set ARGV to the provided IRB args so they can be processed by IRB.
        # Always add --noautocomplete to disable autocomplete (currently broken with Ruby::Box)
        # TODO: Enable autocomplete when it's not broken.
        irb_args_with_noautocomplete = ['--noautocomplete'] + irb_args
        box.eval(<<~RUBY)
          ARGV.replace(#{irb_args_with_noautocomplete.inspect})
          IRB.start
        RUBY
      end
    end
  end
end
