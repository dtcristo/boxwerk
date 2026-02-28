# frozen_string_literal: true

# Global configuration available in all package boxes.
# Defined in boot/ so it's autoloaded in the root box before
# package boxes are created.
module Config
  SHOP_NAME = ENV.fetch('SHOP_NAME', 'Cosmic Coffee')
  CURRENCY = '$'
  POINTS_PER_DOLLAR = 1
end
