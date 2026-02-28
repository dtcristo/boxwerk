# frozen_string_literal: true

require 'bundler/gem_tasks'

STREE_FILES = '**/*.rb **/Rakefile'
EXAMPLES_DIR = File.join(__dir__, 'examples')
EXAMPLE_DIRS =
  Dir.glob(File.join(EXAMPLES_DIR, '*')).select { |d| File.directory?(d) }.sort

task :test do
  $LOAD_PATH.unshift(File.join(__dir__, 'test'))
  Dir.glob('test/boxwerk/**/*_test.rb').sort.each { |f| require_relative f }
end

task :e2e do
  sh('ruby', 'test/e2e_test.rb')
end

namespace :example do
  EXAMPLE_DIRS.each do |dir|
    name = File.basename(dir)
    desc "Run the #{name} example"
    task name.to_sym do
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
  end
end

task examples: EXAMPLE_DIRS.map { |d| "example:#{File.basename(d)}" }

task :format do
  sh "bundle exec stree write #{STREE_FILES}"
end

task default: %i[test e2e examples]
