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
end
