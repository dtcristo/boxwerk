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

    def test_setup_module_exists
      assert_respond_to Setup, :run!
      assert_respond_to Setup, :graph
      assert_respond_to Setup, :booted?
      assert_respond_to Setup, :reset!
    end

    def test_booted_returns_false_initially
      refute Setup.booted?
    end

    def test_graph_returns_nil_initially
      assert_nil Setup.graph
    end

    def test_reset_clears_state
      # Manually set state
      Setup.instance_variable_set(:@booted, true)
      Setup.instance_variable_set(:@graph, 'fake_graph')

      Setup.reset!

      refute Setup.booted?
      assert_nil Setup.graph
    end

    def test_run_raises_without_package_yml
      error = assert_raises(RuntimeError) { Setup.run!(start_dir: @tmpdir) }

      assert_match(/Cannot find package.yml/, error.message)
    end

    def test_run_finds_package_yml_in_current_directory
      create_simple_package(@tmpdir)

      graph = Setup.run!(start_dir: @tmpdir)

      assert_instance_of Graph, graph
      assert Setup.booted?
      assert_equal graph, Setup.graph
    end

    def test_run_finds_package_yml_in_parent_directory
      create_simple_package(@tmpdir)
      nested_dir = File.join(@tmpdir, 'app', 'lib', 'deep')
      FileUtils.mkdir_p(nested_dir)

      graph = Setup.run!(start_dir: nested_dir)

      assert_instance_of Graph, graph
      assert Setup.booted?
    end

    def test_run_searches_up_directory_tree
      create_simple_package(@tmpdir)
      deep_dir = File.join(@tmpdir, 'a', 'b', 'c', 'd')
      FileUtils.mkdir_p(deep_dir)

      graph = Setup.run!(start_dir: deep_dir)

      assert_instance_of Graph, graph
      assert_equal @tmpdir, graph.root.path
    end

    def test_run_with_explicit_start_dir
      create_simple_package(@tmpdir)

      graph = Setup.run!(start_dir: @tmpdir)

      assert_instance_of Graph, graph
    end

    def test_run_defaults_to_pwd
      Dir.chdir(@tmpdir) do
        create_simple_package(@tmpdir)

        graph = Setup.run!

        assert_instance_of Graph, graph
      end
    end

    def test_run_raises_when_no_package_yml_found
      deep_dir = File.join(@tmpdir, 'very', 'deep', 'directory')
      FileUtils.mkdir_p(deep_dir)

      error = assert_raises(RuntimeError) { Setup.run!(start_dir: deep_dir) }

      assert_match(/Cannot find package.yml/, error.message)
    end

    def test_multiple_calls_to_run
      create_simple_package(@tmpdir)

      graph1 = Setup.run!(start_dir: @tmpdir)
      Setup.reset!
      graph2 = Setup.run!(start_dir: @tmpdir)

      assert_instance_of Graph, graph1
      assert_instance_of Graph, graph2
    end

    def test_find_package_yml_stops_at_filesystem_root
      # Start from a deep system directory that won't have package.yml
      system_dir = File.join('/', 'tmp', 'boxwerk_test_' + Time.now.to_i.to_s)
      FileUtils.mkdir_p(system_dir)

      begin
        error =
          assert_raises(RuntimeError) { Setup.run!(start_dir: system_dir) }

        assert_match(/Cannot find package.yml/, error.message)
      ensure
        FileUtils.rm_rf(system_dir)
      end
    end

    def test_setup_creates_graph_with_dependencies
      # Create a package with dependencies
      util_dir = File.join(@tmpdir, 'packages', 'util')
      FileUtils.mkdir_p(File.join(util_dir, 'lib'))
      File.write(
        File.join(util_dir, 'package.yml'),
        YAML.dump({ 'exports' => ['Calculator'] }),
      )

      # Create the actual Calculator implementation
      File.write(
        File.join(util_dir, 'lib', 'calculator.rb'),
        "class Calculator\n  def self.add(a, b)\n    a + b\n  end\nend\n",
      )

      create_package(@tmpdir, imports: ['packages/util'])

      graph = Setup.run!(start_dir: @tmpdir)

      assert_equal 2, graph.packages.size
      assert graph.packages.key?('root')
      assert graph.packages.key?('util')
    end

    private

    def create_simple_package(path)
      create_package(path, exports: ['App'])
    end

    def create_package(path, exports: nil, imports: nil)
      content = {}
      content['exports'] = exports if exports
      content['imports'] = imports if imports

      File.write(File.join(path, 'package.yml'), YAML.dump(content))
    end
  end
end
