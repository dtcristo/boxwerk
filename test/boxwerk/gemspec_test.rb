# frozen_string_literal: true

require 'test_helper'

module Boxwerk
  class GemspecTest < Minitest::Test
    ROOT = File.expand_path('../..', __dir__)

    # The gem ships the library, executable, and user docs only, and the list
    # does not depend on git, so it also builds from a source archive.
    def test_packages_only_library_executable_and_docs
      expected =
        Dir.glob(%w[lib/**/*.rb exe/*], base: ROOT) +
          %w[ARCHITECTURE.md CHANGELOG.md LICENSE.txt README.md USAGE.md]

      assert_equal expected.sort, specification.files.sort
      assert_equal ['boxwerk'], specification.executables
    end

    private

    def specification
      Gem::Specification.load(File.join(ROOT, 'boxwerk.gemspec'))
    end
  end
end
