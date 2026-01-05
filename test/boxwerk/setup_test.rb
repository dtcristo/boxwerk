# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class SetupTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      Setup.reset!
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      Setup.reset!
    end

    def test_run_raises_without_package_yml
      error = assert_raises(RuntimeError) { Setup.run!(start_dir: @tmpdir) }

      assert_match(/Cannot find package.yml/, error.message)
    end

    def test_run_finds_package_yml_and_boots_packages
      create_package(@tmpdir, exports: ['App'])

      graph = Setup.run!(start_dir: @tmpdir)

      assert_instance_of Graph, graph
      assert Setup.booted?
      assert_equal graph, Setup.graph
    end

    def test_run_searches_up_directory_tree
      create_package(@tmpdir, exports: ['App'])
      nested_dir = File.join(@tmpdir, 'app', 'lib', 'deep')
      FileUtils.mkdir_p(nested_dir)

      graph = Setup.run!(start_dir: nested_dir)

      assert_instance_of Graph, graph
      assert_equal @tmpdir, graph.root.path
    end

    def test_reset_clears_state
      create_package(@tmpdir, exports: ['App'])
      Setup.run!(start_dir: @tmpdir)

      Setup.reset!

      refute Setup.booted?
      assert_nil Setup.graph
    end

    private

    def create_package(path, exports: nil, imports: nil)
      content = {}
      content['exports'] = exports if exports
      content['imports'] = imports if imports

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
