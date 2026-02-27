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

desc 'Run all tests (unit, integration, e2e)'
task all: %i[test e2e]

task default: :test
