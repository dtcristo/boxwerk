# frozen_string_literal: true

module Boxwerk
  # Lightweight Gemfile parser that extracts autorequire directives.
  #
  # Evaluates a Gemfile in a sandbox that only captures `gem` calls,
  # avoiding Bundler::Dsl side-effects. Handles:
  #   gem 'name'                → nil   (require the gem name)
  #   gem 'name', require: false → []   (skip)
  #   gem 'name', require: 'x'  → ["x"] (require specific paths)
  class GemfileRequireParser
    attr_reader :requires

    def initialize
      @requires = {}
    end

    def eval_gemfile(path)
      instance_eval(File.read(path), path)
    end

    private

    def source(*); end
    def ruby(*); end
    def git_source(*); end
    def platform(*); end
    def platforms(*); end
    def group(*); end
    def install_if(*); end
    def plugin(*); end

    def gem(name, *args)
      opts = args.last.is_a?(Hash) ? args.last : {}

      if opts.key?(:require)
        val = opts[:require]
        @requires[name] =
          case val
          when false then []
          when String then [val]
          when Array then val
          else nil
          end
      else
        @requires[name] = nil
      end
    end
  end
end
