# frozen_string_literal: true

# Add services/ as an additional autoload directory
Boxwerk.package.autoloader.push_dir('services')

# Monkey-patch String with a kitchen-specific helper.
# This patch is isolated to the kitchen box — it won't leak
# into other packages or the global context.
class String
  def to_order_ticket
    "🎫 #{upcase}"
  end
end
