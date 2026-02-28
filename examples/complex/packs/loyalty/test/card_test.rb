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
end
