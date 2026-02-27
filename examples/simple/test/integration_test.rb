# frozen_string_literal: true

require 'minitest/autorun'

class IntegrationTest < Minitest::Test
  def test_invoice_accessible
    invoice = Invoice.new(tax_rate: 0.15)
    invoice.add_item('Test', 10_000)
    assert_equal 11_500, invoice.total
  end

  def test_greeting_accessible
    assert_kind_of String, Greeting.hello
  end

  def test_transitive_dependency_blocked
    assert_raises(NameError) { Calculator }
  end

  def test_private_constant_blocked
    assert_raises(NameError) { TaxCalculator }
  end

  def test_faker_version_isolation
    finance_version = Invoice.faker_version
    greeting_version = Greeting.faker_version
    refute_equal finance_version,
                 greeting_version,
                 'Expected different faker versions in different packs'
  end

  def test_greeting_includes_prefix
    greeting = Greeting.hello
    assert greeting.start_with?('Hello, '),
           'Expected greeting to start with GREETING_PREFIX from .env'
  end

  def test_dotenv_accessible_as_global_gem
    assert defined?(Dotenv),
           'Global gem dotenv should be accessible in root package'
  end

  def test_private_class_instance_from_public_method
    invoice = Invoice.new
    invoice.add_item('Widget', 5_000)
    item = invoice.items.first
    assert_equal 'Widget', item.description
    assert_equal 5_000, item.amount_cents
    assert_equal 'LineItem', item.class.name
  end

  def test_private_line_item_constant_blocked
    assert_raises(NameError) { LineItem }
  end
end
