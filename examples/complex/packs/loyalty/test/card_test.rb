# frozen_string_literal: true

require 'minitest/autorun'

class CardTest < Minitest::Test
  def test_earn_points
    card = Loyalty::Card.new(member_name: 'Alice')
    card.earn(550)
    assert_equal 5, card.points
  end

  def test_to_s
    card = Loyalty::Card.new(member_name: 'Bob')
    card.earn(1200)
    assert_equal 'Bob: 12 pts', card.to_s
  end

  def test_faker_generates_name
    card = Loyalty::Card.new
    refute_nil card.member_name
    refute_empty card.member_name
  end

  # Isolation: loyalty has no dependencies.
  # Constants from all other packages must not be accessible.
  def test_cannot_access_menu
    assert_raises(NameError) { Menu }
  end

  def test_cannot_access_orders
    assert_raises(NameError) { Orders }
  end

  def test_cannot_access_kitchen
    assert_raises(NameError) { Kitchen }
  end
end
