# frozen_string_literal: true

module Analytics
  class Report
    def initialize(name)
      @name = name
    end

    def to_s
      "Report: #{@name}"
    end
  end
end
