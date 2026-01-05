# frozen_string_literal: true

module Boxwerk
  # CLI parses commands and delegates to Setup for package management.
  # Handles run, console, and help commands.
  module CLI
    class << self
      def run(argv)
        if argv.empty?
          print_usage
          exit 1
        end

        case argv[0]
        when 'run'
          run_command(argv[1..-1])
        when 'console'
          console_command(argv[1..-1])
        when 'help', '--help', '-h'
          print_usage
          exit 0
        else
          puts "Error: Unknown command '#{argv[0]}'"
          puts ''
          print_usage
          exit 1
        end
      end

      private

      def print_usage
        puts 'Boxwerk - Ruby package system with Box-powered constant isolation'
        puts ''
        puts 'Usage: boxwerk <command> [args...]'
        puts ''
        puts 'Commands:'
        puts '  run <script.rb> [args...]    Run a script in the root package context'
        puts '  console [irb-args...]        Start an IRB console in the root package context'
        puts '  help                         Show this help message'
      end

      def run_command(args)
        if args.empty?
          puts 'Error: No script specified'
          puts ''
          puts 'Usage: boxwerk run <script.rb> [args...]'
          exit 1
        end

        script_path = args[0]
        unless File.exist?(script_path)
          puts "Error: Script not found: #{script_path}"
          exit 1
        end

        graph = perform_setup
        execute_in_box(graph.root.box, script_path, args[1..-1] || [])
      end

      def console_command(args)
        require 'irb'
        graph = perform_setup
        start_console_in_box(graph.root.box, args)
      end

      def perform_setup
        Boxwerk::Setup.run!(start_dir: Dir.pwd)
      rescue => e
        puts "Error: #{e.message}"
        exit 1
      end

      def execute_in_box(box, script_path, script_args)
        box.eval("ARGV.replace(#{script_args.inspect})")
        box.require(File.expand_path(script_path))
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

        box.eval(<<~RUBY)
          ARGV.replace(#{(['--noautocomplete'] + irb_args).inspect})
          IRB.start
        RUBY
      end
    end
  end
end
