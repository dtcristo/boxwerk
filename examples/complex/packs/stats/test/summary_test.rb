# frozen_string_literal: true

require 'minitest/autorun'

class SummaryTest < Minitest::Test
  def test_print_runs_without_error
    # Touch classes to trigger autoload of data store setup
    Menu::Item
    Orders::Order
    Loyalty::Card
    assert_output(/Stats/) { Stats::Summary.print }
  end
end
