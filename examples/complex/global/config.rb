# frozen_string_literal: true

# Global configuration available in all package boxes.
# Defined in global/ so it's autoloaded in the global context before
# package boxes are created.
module Config
  SHOP_NAME = ENV.fetch('SHOP_NAME', 'Cosmic Coffee')
  CURRENCY = '$'
  POINTS_PER_DOLLAR = 1
end
