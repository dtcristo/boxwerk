# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'

Minitest::TestTask.create

desc 'Run end-to-end tests'
task :e2e do
  sh 'ruby test/e2e/run.rb'
end

STREE_FILES = '**/*.rb **/Rakefile'

desc 'Format code with syntax_tree'
task :format do
  sh "bundle exec stree write #{STREE_FILES}"
end

EXAMPLES_DIR = File.join(__dir__, 'examples')

# Discover examples that have tests (Rakefile present).
EXAMPLE_DIRS =
  Dir.glob(File.join(EXAMPLES_DIR, '*')).select { |d| File.directory?(d) }.sort

desc 'Run example apps (assert successful exit)'
task :example_apps do
  EXAMPLE_DIRS.each do |dir|
    main = %w[main.rb app.rb].find { |f| File.exist?(File.join(dir, f)) }
    next unless main

    name = File.basename(dir)
    puts "==> example:#{name} #{main}"
    sh(
      { 'RUBY_BOX' => '1' },
      File.join(dir, 'bin', 'boxwerk'),
      'run',
      main,
      chdir: dir,
    )
  end
end

desc 'Run example test suites'
task :example_tests do
  EXAMPLE_DIRS.each do |dir|
    next unless File.exist?(File.join(dir, 'Rakefile'))

    name = File.basename(dir)
    puts "==> example:#{name} tests"
    sh(
      { 'RUBY_BOX' => '1' },
      File.join(dir, 'bin', 'boxwerk'),
      'exec',
      '--all',
      'rake',
      'test',
      chdir: dir,
    )
  end
end

desc 'Run all example apps and tests'
task examples: %i[example_apps example_tests]

desc 'Run all tests (unit, integration, e2e, examples)'
task all: %i[test e2e examples]

task default: :all
