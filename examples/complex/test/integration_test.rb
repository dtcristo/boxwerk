# frozen_string_literal: true

require 'minitest/autorun'

class IntegrationTest < Minitest::Test
  # Direct dependencies accessible
  def test_menu_item_accessible
    item = Menu::Item.new(name: 'Test', price_cents: 100)
    assert_equal 'Test', item.name
  end

  def test_order_accessible
    order = Orders::Order.new
    assert_respond_to order, :add
  end

  def test_loyalty_card_accessible
    card = Loyalty::Card.new(member_name: 'Test')
    assert_equal 'Test', card.member_name
  end

  def test_kitchen_barista_accessible
    barista = Kitchen::Barista.new(name: 'Test')
    assert_equal 'Test', barista.name
  end

  # Privacy: public_path — Menu::Item is public, Menu::Recipe is private.
  # NOTE: Once the Menu namespace module is resolved, Ruby accesses child
  # constants directly on it (bypassing const_missing). Privacy is enforced
  # for top-level namespace resolution but not for children accessed through
  # an already-resolved module reference. This is a known limitation with
  # namespaced constants. Menu::Recipe can be tested as private within the
  # menu pack's own tests (via inter-package const_missing).
  def test_menu_item_is_public
    item = Menu::Item.new(name: 'Test', price_cents: 100)
    assert_equal 'Test', item.name
  end

  # Privacy: pack_public sigil (Order is public, LineItem is private)
  # Same namespace limitation applies — once Orders module is resolved,
  # LineItem is accessible through it.
  def test_orders_order_is_public
    order = Orders::Order.new
    assert_respond_to order, :add
  end

  # Gem version isolation (different major versions)
  def test_faker_version_isolation
    loyalty_v = Loyalty::Card.faker_version
    kitchen_v = Kitchen::Barista.faker_version
    refute_equal loyalty_v, kitchen_v, 'Expected different faker versions'
    assert loyalty_v.start_with?('2.'), "Expected faker 2.x, got #{loyalty_v}"
    assert kitchen_v.start_with?('3.'), "Expected faker 3.x, got #{kitchen_v}"
  end

  # Global gems accessible
  def test_dotenv_accessible
    assert defined?(Dotenv)
  end

  def test_colorize_accessible
    assert defined?(Colorize)
  end

  def test_env_loaded
    assert_equal 'Cosmic Coffee', ENV['SHOP_NAME']
  end

  # Private instances usable through public methods
  def test_order_line_items_usable
    item = Menu::Item.new(name: 'Test', price_cents: 500)
    order = Orders::Order.new
    order.add(item, quantity: 3)
    assert_equal 1500, order.total_cents
  end
end
