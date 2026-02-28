# frozen_string_literal: true

require 'minitest/autorun'

class SummaryTest < Minitest::Test
  def test_print_runs_without_error
    assert_output(/Stats/) { Stats::Summary.print }
  end
end
