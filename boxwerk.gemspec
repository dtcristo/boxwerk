# frozen_string_literal: true

require_relative 'lib/boxwerk/version'

Gem::Specification.new do |spec|
  spec.name = 'boxwerk'
  spec.version = Boxwerk::VERSION
  spec.authors = ['David Cristofaro']
  spec.email = ['david@dtcristo.com']

  spec.summary = 'Ruby package system with Box-powered constant isolation'
  spec.description =
    'Boxwerk is an experimental Ruby package system with Box-powered constant isolation. It is used at runtime to organize code into packages with explicit dependencies and strict constant access using Ruby::Box. Inspired by Packwerk.'
  spec.homepage = 'https://github.com/dtcristo/boxwerk'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/dtcristo/boxwerk'
  spec.metadata[
    'changelog_uri'
  ] = 'https://github.com/dtcristo/boxwerk/blob/main/CHANGELOG.md'

  gemspec = File.basename(__FILE__)
  spec.files =
    IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls
        .readlines("\x0", chomp: true)
        .reject do |f|
          (f == gemspec) ||
            f.start_with?(*%w[bin/ example/ test/ .github/ Gemfile .gitignore])
        end
    end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'irb', '~> 1.16'
end
