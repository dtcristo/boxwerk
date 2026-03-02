# frozen_string_literal: true

require 'minitest/autorun'

class BaristaTest < Minitest::Test
  def test_prepare
    item = Menu::Item.new(name: 'Latte', price_cents: 550)
    barista = Kitchen::Barista.new(name: 'Alex')
    assert_equal 'Alex is preparing 🎫 LATTE (3 in queue)', barista.prepare(item)
  end

  def test_faker_generates_name
    barista = Kitchen::Barista.new
    refute_nil barista.name
    refute_empty barista.name
  end

  # Isolation: kitchen depends only on packs/menu.
  # Constants from packages that are not direct dependencies are blocked.
  #
  # Note: qualified access via a shared namespace (e.g. Menu::Recipe) is not
  # blocked at the box level once the parent module is resolved — this is a
  # known limitation of the Ruby::Box approach.
  def test_cannot_access_orders
    assert_raises(NameError) { Orders }
  end

  def test_cannot_access_loyalty
    assert_raises(NameError) { Loyalty }
  end
end
