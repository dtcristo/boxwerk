# frozen_string_literal: true

require 'bundler/gem_tasks'

STREE_FILES = '**/*.rb **/Rakefile'
EXAMPLES_DIR = File.join(__dir__, 'examples')
EXAMPLE_DIRS =
  Dir.glob(File.join(EXAMPLES_DIR, '*')).select { |d| File.directory?(d) }.sort

desc 'Run all tests (unit, integration, e2e)'
task :test do
  $LOAD_PATH.unshift(File.join(__dir__, 'test'))
  Dir.glob('test/boxwerk/**/*_test.rb').sort.each { |f| require_relative f }
  sh 'ruby test/e2e_test.rb'
end

desc 'Run a specific example (e.g. rake example[complex])'
task :example, [:name] do |_t, args|
  name = args[:name] || abort('Usage: rake example[name]')
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

  # Run e2e tests if present
  e2e = File.join(dir, 'test', 'e2e_test.rb')
  if File.exist?(e2e)
    puts "==> example:#{name} e2e"
    sh({ 'RUBY_BOX' => '1' }, 'ruby', e2e, chdir: dir)
  end
end

desc 'Run all examples'
task :examples do
  EXAMPLE_DIRS.each do |dir|
    name = File.basename(dir)
    puts "==> example:#{name}"
    sh(
      { 'RUBY_BOX' => '1' },
      File.join(dir, 'bin', 'boxwerk'),
      'exec',
      '--all',
      'rake',
      chdir: dir,
    )

    # Run e2e tests if present
    e2e = File.join(dir, 'test', 'e2e_test.rb')
    if File.exist?(e2e)
      puts "==> example:#{name} e2e"
      sh({ 'RUBY_BOX' => '1' }, 'ruby', e2e, chdir: dir)
    end
  end
end

desc 'Format code with syntax_tree'
task :format do
  sh "bundle exec stree write #{STREE_FILES}"
end

task default: %i[test examples]
