# frozen_string_literal: true

require_relative 'lib/boxwerk/version'

Gem::Specification.new do |spec|
  spec.name = 'boxwerk'
  spec.version = Boxwerk::VERSION
  spec.authors = ['David Cristofaro']
  spec.email = ['david@dtcristo.com']

  spec.summary = 'Ruby package system with Box-powered boundary enforcement'
  spec.description =
    'Boxwerk is a tool for creating modular Ruby and Rails applications. ' \
      'It organizes code into packages with clear boundaries and explicit dependencies, ' \
      'enforcing them at runtime using Ruby::Box constant isolation. ' \
      'It reads standard Packwerk package.yml files (without requiring Packwerk), ' \
      'providing per-package gem isolation, Zeitwerk-based autoloading, ' \
      'monkey patch isolation between packages, and a CLI for running, ' \
      'testing, and inspecting your modular application.'
  spec.homepage = 'https://github.com/dtcristo/boxwerk'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0.1'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/dtcristo/boxwerk'
  spec.metadata[
    'changelog_uri'
  ] = 'https://github.com/dtcristo/boxwerk/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://dtcristo.github.io/boxwerk/'

  gemspec = File.basename(__FILE__)
  spec.files =
    IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls
        .readlines("\x0", chomp: true)
        .reject do |f|
          (f == gemspec) ||
            f.start_with?(
              *%w[
                bin/
                example/
                examples/
                test/
                .github/
                .gitignore
                .mise
                .stree
                gems.
              ],
            )
        end
    end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'bundler', '~> 4.0'
  spec.add_dependency 'irb', '~> 1.17'
  spec.add_dependency 'zeitwerk', '~> 2.7'
end
