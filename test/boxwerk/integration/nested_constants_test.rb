# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for nested module/class constants and intra-package structure.
  class NestedConstantsIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_nested_module_constant
      a_dir = create_package_dir('a')
      create_package(a_dir)

      FileUtils.mkdir_p(File.join(a_dir, 'lib', 'services'))
      File.write(
        File.join(a_dir, 'lib', 'services', 'billing.rb'),
        "module Services\n  class Billing\n    def self.charge\n      'charged'\n    end\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'charged', root_box.eval('A::Services::Billing.charge')
    end

    def test_deeply_nested_constant
      a_dir = create_package_dir('a')
      create_package(a_dir)

      FileUtils.mkdir_p(File.join(a_dir, 'lib', 'api', 'v2'))
      File.write(
        File.join(a_dir, 'lib', 'api', 'v2', 'endpoint.rb'),
        "module Api\n  module V2\n    class Endpoint\n      def self.url\n        '/api/v2'\n      end\n    end\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal '/api/v2', root_box.eval('A::Api::V2::Endpoint.url')
    end

    def test_intra_package_require
      a_dir = create_package_dir('a')
      create_package(a_dir)

      File.write(
        File.join(a_dir, 'lib', 'helper.rb'),
        "class Helper\n  def self.greet\n    'hello'\n  end\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'greeter.rb'),
        "class Greeter\n  def self.greet\n    Helper.greet + ' world'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'hello world', root_box.eval('A::Greeter.greet')
    end

    def test_cross_package_method_call
      util_dir = create_package_dir('util')
      create_package(util_dir)
      File.write(
        File.join(util_dir, 'lib', 'formatter.rb'),
        <<~RUBY,
          class Formatter
            def self.format(val)
              "[" + val.to_s + "]"
            end
          end
        RUBY
      )

      app_dir = create_package_dir('app')
      create_package(app_dir, dependencies: ['packages/util'])
      File.write(
        File.join(app_dir, 'lib', 'display.rb'),
        "class Display\n  def self.show(val)\n    Util::Formatter.format(val)\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/app'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal '[42]', root_box.eval('App::Display.show(42)')
    end

    def test_multiple_files_same_module
      a_dir = create_package_dir('a')
      create_package(a_dir)

      FileUtils.mkdir_p(File.join(a_dir, 'lib', 'ops'))
      File.write(
        File.join(a_dir, 'lib', 'ops', 'add.rb'),
        "module Ops\n  class Add\n    def self.call(a, b) = a + b\n  end\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'ops', 'multiply.rb'),
        "module Ops\n  class Multiply\n    def self.call(a, b) = a * b\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packages/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 5, root_box.eval('A::Ops::Add.call(2, 3)')
      assert_equal 6, root_box.eval('A::Ops::Multiply.call(2, 3)')
    end
  end
end
