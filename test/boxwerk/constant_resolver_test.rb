# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class ConstantResolverTest < Minitest::Test
    def test_build_resolver_returns_proc
      resolver = ConstantResolver.build_resolver([])
      assert_kind_of Proc, resolver
    end

    def test_nameerror_includes_hint_for_non_dependency
      pkg = Package.new(name: 'packs/util')
      ref = {
        file_indexes: { 'packs/util' => { 'Foo' => '/tmp/foo.rb' } },
        packages: { 'packs/util' => pkg },
        root_path: '/tmp',
        dep_names: Set.new,
        self_name: 'packs/billing',
      }
      resolver =
        ConstantResolver.build_resolver(
          [],
          all_packages_ref: ref,
          package_name: 'packs/billing',
        )

      error = assert_raises(NameError) { resolver.call(:Foo) }
      assert_equal(
        "uninitialized constant Foo (defined in 'packs/util', not a dependency of 'packs/billing')",
        error.message,
      )
      assert_equal :Foo, error.name
    end

    def test_nameerror_includes_privacy_hint
      pkg =
        Package.new(name: 'packs/util', config: { 'enforce_privacy' => true })
      ref = {
        file_indexes: { 'packs/util' => { 'Foo' => '/tmp/foo.rb' } },
        packages: { 'packs/util' => pkg },
        root_path: '/tmp',
        dep_names: Set.new,
        self_name: 'packs/billing',
      }
      resolver =
        ConstantResolver.build_resolver(
          [],
          all_packages_ref: ref,
          package_name: 'packs/billing',
        )

      error = assert_raises(NameError) { resolver.call(:Foo) }
      assert_equal(
        "uninitialized constant Foo (private in 'packs/util', not a dependency of 'packs/billing')",
        error.message,
      )
      assert_equal :Foo, error.name
    end

    def test_nameerror_no_hint_when_truly_missing
      resolver =
        ConstantResolver.build_resolver(
          [],
          all_packages_ref: nil,
          package_name: 'packs/billing',
        )

      error = assert_raises(NameError) { resolver.call(:Foo) }
      assert_equal 'uninitialized constant Foo', error.message
      assert_equal :Foo, error.name
    end
  end
end
