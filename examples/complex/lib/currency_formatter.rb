# frozen_string_literal: true

# Shared utility available in all package boxes via the global autoloader.
# Loaded via Boxwerk.global.autoloader.push_dir in global/boot.rb.
module CurrencyFormatter
  def self.format(cents)
    sprintf("#{Config::CURRENCY}%.2f", cents / 100.0)
  end
end
