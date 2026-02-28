# frozen_string_literal: true

require 'bundler/gem_tasks'

STREE_FILES = '**/*.rb **/Rakefile'
EXAMPLES_DIR = File.join(__dir__, 'examples')
EXAMPLE_DIRS =
  Dir.glob(File.join(EXAMPLES_DIR, '*')).select { |d| File.directory?(d) }.sort

desc 'Run unit tests'
task :test do
  $LOAD_PATH.unshift(File.join(__dir__, 'test'))
  Dir.glob('test/boxwerk/**/*_test.rb').sort.each { |f| require_relative f }
end

desc 'Run e2e tests'
task :e2e do
  sh('ruby', 'test/e2e_test.rb')
end

def run_example(name)
  dir = File.join(EXAMPLES_DIR, name)
  abort("Example not found: #{name}") unless File.directory?(dir)

  puts "==> example:#{name}"
  sh(
    { 'RUBY_BOX' => '1' },
    File.join(dir, 'bin', 'boxwerk'),
    'exec',
    '--all',
    'rake',
    chdir: dir,
  )
end

desc 'Run a specific example (e.g. rake example minimal)'
task :example do
  name = ARGV[1] || abort('Usage: rake example <name>')
  run_example(name)
  exit
end

desc 'Run all examples'
task :examples do
  EXAMPLE_DIRS.each { |dir| run_example(File.basename(dir)) }
end

desc 'Format code with syntax_tree'
task :format do
  sh "bundle exec stree write #{STREE_FILES}"
end

task default: %i[test e2e examples]
