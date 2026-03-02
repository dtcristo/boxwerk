# frozen_string_literal: true

require 'minitest/autorun'

class ItemTest < Minitest::Test
  def test_price_formatting
    item = Menu::Item.new(name: 'Latte', price_cents: 550)
    assert_equal '$5.50', item.price
  end

  def test_to_s
    item = Menu::Item.new(name: 'Espresso', price_cents: 350)
    assert_equal 'Espresso ($3.50)', item.to_s
  end

  def test_default_category
    item = Menu::Item.new(name: 'Tea', price_cents: 300)
    assert_equal :drink, item.category
  end

  def test_recipe_accessible_internally
    recipe =
      Menu::Recipe.new(
        item: Menu::Item.new(name: 'Latte', price_cents: 550),
        steps: %w[grind brew steam pour],
      )
    assert_equal 'grind → brew → steam → pour', recipe.instruction
  end

  # Isolation: menu has no dependencies, so constants from other packages
  # must not be accessible.
  def test_cannot_access_orders
    assert_raises(NameError) { Orders }
  end

  def test_cannot_access_loyalty
    assert_raises(NameError) { Loyalty }
  end

  def test_cannot_access_kitchen
    assert_raises(NameError) { Kitchen }
  end
end
