# frozen_string_literal: true

require_relative 'lib/boxwerk/version'

Gem::Specification.new do |spec|
  spec.name = 'boxwerk'
  spec.version = Boxwerk::VERSION
  spec.authors = ['David Cristofaro']
  spec.email = ['david@dtcristo.com']

  spec.summary = 'Runtime enforcement companion to Packwerk using Ruby::Box'
  spec.description =
    'Boxwerk is the runtime enforcement companion to Packwerk. While Packwerk provides static analysis of package dependencies, Boxwerk enforces those boundaries at runtime using Ruby::Box constant isolation.'
  spec.homepage = 'https://github.com/dtcristo/boxwerk'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0.1'

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
  spec.add_dependency 'packwerk'
  spec.add_dependency 'zeitwerk'
end
