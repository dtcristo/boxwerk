# frozen_string_literal: true

require_relative 'test_helper'

module Boxwerk
  # Tests for privacy enforcement: public path, pack_public sigil,
  # private_constants, and descriptive error messages.
  class PrivacyIntegrationTest < Minitest::Test
    include IntegrationTestHelper

    def test_privacy_blocks_private_constant
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)

      pub_dir = File.join(a_dir, 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\n  def self.value\n    'public'\n  end\nend\n")
      File.write(File.join(a_dir, 'lib', 'secret.rb'), "class Secret\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'public', root_box.eval('Invoice.value')
      assert_raises(NameError) { root_box.eval('Secret') }
    end

    def test_privacy_allows_all_when_not_enforced
      a_dir = create_package_dir('a')
      create_package(a_dir)
      File.write(
        File.join(a_dir, 'lib', 'secret.rb'),
        "class Secret\n  def self.value\n    'accessible'\n  end\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'accessible', root_box.eval('Secret.value')
    end

    def test_privacy_pack_public_sigil
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)

      File.write(
        File.join(a_dir, 'lib', 'publicized.rb'),
        "# pack_public: true\nclass Publicized\n  def self.value\n    'sigil'\n  end\nend\n",
      )
      File.write(
        File.join(a_dir, 'lib', 'private_thing.rb'),
        "class PrivateThing\nend\n",
      )

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'sigil', root_box.eval('Publicized.value')
      assert_raises(NameError) { root_box.eval('PrivateThing') }
    end

    def test_privacy_explicit_private_constants
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true, private_constants: ['::Invoice'])

      pub_dir = File.join(a_dir, 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\nend\n")
      File.write(File.join(pub_dir, 'report.rb'), "class Report\n  def self.value\n    'report'\n  end\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      assert_equal 'report', root_box.eval('Report.value')
      assert_raises(NameError) { root_box.eval('Invoice') }
    end

    def test_descriptive_error_for_privacy_violation
      a_dir = create_package_dir('a')
      create_package(a_dir, enforce_privacy: true)
      File.write(File.join(a_dir, 'lib', 'secret.rb'), "class Secret\nend\n")

      create_package(@tmpdir, dependencies: ['packs/a'])

      result = boot_system
      root_box = result[:box_manager].boxes['.']

      error = assert_raises(NameError) { root_box.eval('Secret') }
      assert_match(/Privacy violation/, error.message)
      assert_match(/packs\/a/, error.message)
    end
  end
end
