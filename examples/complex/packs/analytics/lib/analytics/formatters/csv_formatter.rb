# frozen_string_literal: true

# This file is in a collapse_dir — Analytics::Formatters is collapsed so
# this class is accessible as Analytics::CsvFormatter (not Formatters::CsvFormatter).
module Analytics
  class CsvFormatter
    def format(report)
      "csv: #{report}"
    end
  end
end
