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
end
