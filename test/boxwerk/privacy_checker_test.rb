# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Boxwerk
  class PrivacyCheckerTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_enforces_privacy_when_true
      pkg = create_package('packs/a', 'enforce_privacy' => true)
      assert PrivacyChecker.enforces_privacy?(pkg)
    end

    def test_enforces_privacy_when_strict
      pkg = create_package('packs/a', 'enforce_privacy' => 'strict')
      assert PrivacyChecker.enforces_privacy?(pkg)
    end

    def test_does_not_enforce_privacy_when_false
      pkg = create_package('packs/a', 'enforce_privacy' => false)
      refute PrivacyChecker.enforces_privacy?(pkg)
    end

    def test_does_not_enforce_privacy_when_nil
      pkg = create_package('packs/a', {})
      refute PrivacyChecker.enforces_privacy?(pkg)
    end

    def test_default_public_path
      pkg = create_package('packs/a', {})
      path = PrivacyChecker.public_path_for(pkg, @tmpdir)
      assert_equal File.join(@tmpdir, 'packs/a', 'public/'), path
    end

    def test_custom_public_path
      pkg = create_package('packs/a', 'public_path' => 'lib/public')
      path = PrivacyChecker.public_path_for(pkg, @tmpdir)
      assert_equal File.join(@tmpdir, 'packs/a', 'lib/public/'), path
    end

    def test_public_constants_from_public_path
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      pub_dir = File.join(pkg_dir, 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\nend\n")
      File.write(File.join(pub_dir, 'report.rb'), "class Report\nend\n")

      # Also create a private file
      lib_dir = File.join(pkg_dir, 'lib')
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, 'secret.rb'), "class Secret\nend\n")

      pkg = create_package('packs/a', 'enforce_privacy' => true)
      consts = PrivacyChecker.public_constants(pkg, @tmpdir)

      assert_includes consts, 'Invoice'
      assert_includes consts, 'Report'
      refute_includes consts, 'Secret'
    end

    def test_public_constants_nil_when_privacy_not_enforced
      pkg = create_package('packs/a', {})
      consts = PrivacyChecker.public_constants(pkg, @tmpdir)
      assert_nil consts
    end

    def test_pack_public_sigil_makes_constant_public
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      lib_dir = File.join(pkg_dir, 'lib')
      FileUtils.mkdir_p(lib_dir)

      File.write(
        File.join(lib_dir, 'publicized.rb'),
        "# pack_public: true\nclass Publicized\nend\n",
      )
      File.write(
        File.join(lib_dir, 'private_thing.rb'),
        "class PrivateThing\nend\n",
      )

      pkg = create_package('packs/a', 'enforce_privacy' => true)
      consts = PrivacyChecker.public_constants(pkg, @tmpdir)

      assert_includes consts, 'Publicized'
      refute_includes consts, 'PrivateThing'
    end

    def test_private_constants_list
      pkg =
        create_package(
          'packs/a',
          'enforce_privacy' => true,
          'private_constants' => %w[::Bar ::Baz],
        )

      privates = PrivacyChecker.private_constants_list(pkg)
      assert_includes privates, 'Bar'
      assert_includes privates, 'Baz'
    end

    def test_accessible_blocks_private_constant
      pkg =
        create_package(
          'packs/a',
          'enforce_privacy' => true,
          'private_constants' => ['::Secret'],
        )

      refute PrivacyChecker.accessible?('Secret', pkg, @tmpdir)
    end

    def test_accessible_allows_public_constant
      pkg_dir = File.join(@tmpdir, 'packs', 'a')
      pub_dir = File.join(pkg_dir, 'public')
      FileUtils.mkdir_p(pub_dir)
      File.write(File.join(pub_dir, 'invoice.rb'), "class Invoice\nend\n")

      pkg = create_package('packs/a', 'enforce_privacy' => true)

      assert PrivacyChecker.accessible?('Invoice', pkg, @tmpdir)
    end

    def test_accessible_all_when_privacy_not_enforced
      pkg = create_package('packs/a', {})

      assert PrivacyChecker.accessible?('Anything', pkg, @tmpdir)
    end

    private

    def create_package(name, config)
      Package.new(name: name, config: config)
    end
  end
end
