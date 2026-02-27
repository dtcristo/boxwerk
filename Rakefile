# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'

Minitest::TestTask.create

desc 'Run end-to-end tests'
task :e2e do
  sh 'ruby test/e2e/run.rb'
end

STREE_FILES =
  'lib/**/*.rb exe/**/* test/**/*.rb Rakefile ' \
    'examples/**/*.rb examples/**/Rakefile'

desc 'Check formatting with syntax_tree'
task :fmt_check do
  sh "bundle exec stree check #{STREE_FILES}"
end

desc 'Format code with syntax_tree'
task :fmt do
  sh "bundle exec stree write #{STREE_FILES}"
end

desc 'Run all tests (unit, integration, e2e)'
task all: %i[test e2e]

task default: :test
