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
    refute_equal finance_version, greeting_version,
      'Expected different faker versions in different packs'
  end
end
