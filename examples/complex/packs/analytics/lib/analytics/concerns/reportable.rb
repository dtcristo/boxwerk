# frozen_string_literal: true

# Concerns dir for mixins — collapsed so modules are at Analytics:: namespace.
module Analytics
  module Concerns
    module Reportable
      def report_name
        self.class.name
      end
    end
  end
end
