# frozen_string_literal: true

require 'minitest/autorun'

class AnalyticsTest < Minitest::Test
  def test_report_accessible
    report = Analytics::Report.new('Sales')
    assert_equal 'Report: Sales', report.to_s
  end

  def test_csv_formatter_collapsed
    # collapse_dirs on lib/analytics/formatters — CsvFormatter is promoted to
    # Analytics namespace (not Analytics::Formatters::CsvFormatter).
    formatter = Analytics::CsvFormatter.new
    assert_equal 'csv: test report', formatter.format('test report')
    # The intermediate Formatters namespace should not be accessible.
    assert_raises(NameError) { Analytics::Formatters }
  end

  def test_legacy_dir_ignored
    # ignore_dirs on lib/analytics/legacy — OldReport must not be autoloaded.
    assert_raises(NameError) { Analytics::Legacy::OldReport }
  end

  # Isolation: analytics has no declared dependencies.
  # Constants from all other packages must not be accessible.
  def test_cannot_access_menu
    assert_raises(NameError) { Menu }
  end

  def test_cannot_access_orders
    assert_raises(NameError) { Orders }
  end

  def test_cannot_access_loyalty
    assert_raises(NameError) { Loyalty }
  end

  def test_cannot_access_kitchen
    assert_raises(NameError) { Kitchen }
  end

  def test_cannot_access_stats
    assert_raises(NameError) { Stats }
  end
end
