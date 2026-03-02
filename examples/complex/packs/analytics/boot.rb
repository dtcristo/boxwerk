# frozen_string_literal: true

# Collapse formatters/ so its constants are promoted to the Analytics namespace
# (e.g. Analytics::CsvFormatter instead of Analytics::Formatters::CsvFormatter).
Boxwerk.package.autoloader.collapse('lib/analytics/formatters')

# Ignore legacy/ so its files are not autoloaded at all.
Boxwerk.package.autoloader.ignore('lib/analytics/legacy')
