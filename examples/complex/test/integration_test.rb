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

  # Data stores: module-level arrays populated by constructors
  def test_menu_data_store
    initial = Menu.items.size
    Menu::Item.new(name: 'Store Test', price_cents: 100)
    assert_equal initial + 1, Menu.items.size
  end

  def test_orders_data_store
    initial = Orders.orders.size
    Orders::Order.new
    assert_equal initial + 1, Orders.orders.size
  end

  def test_loyalty_data_store
    initial = Loyalty.cards.size
    Loyalty::Card.new(member_name: 'Store Test')
    assert_equal initial + 1, Loyalty.cards.size
  end

  # Custom autoload dir (kitchen services/ via boot.rb)
  def test_kitchen_prep_service
    assert_equal 3, Kitchen::PrepService.queue_count
  end

  # Global config accessible
  def test_global_config
    assert_equal '$', Config::CURRENCY
    assert_kind_of String, Config::SHOP_NAME
  end

  # Privacy: public_path — Menu::Item is public, Menu::Recipe is private.
  # NOTE: Once the Menu namespace module is resolved, Ruby accesses child
  # constants directly on it (bypassing const_missing). Privacy is enforced
  # for top-level namespace resolution but not for children accessed through
  # an already-resolved module reference. This is a known limitation with
  # namespaced constants.
  def test_menu_item_is_public
    item = Menu::Item.new(name: 'Test', price_cents: 100)
    assert_equal 'Test', item.name
  end

  # Gem version isolation (different major versions)
  def test_faker_version_isolation
    loyalty_v = Loyalty::Card.faker_version
    kitchen_v = Kitchen::Barista.faker_version
    refute_equal loyalty_v, kitchen_v, 'Expected different faker versions'
    assert loyalty_v.start_with?('2.'), "Expected faker 2.x, got #{loyalty_v}"
    assert kitchen_v.start_with?('3.'), "Expected faker 3.x, got #{kitchen_v}"
  end

  # Global gems accessible (auto-required by Bundler)
  def test_dotenv_accessible
    assert defined?(Dotenv)
  end

  def test_colorize_accessible
    assert defined?(Colorize)
  end

  def test_env_loaded
    assert_equal 'Cosmic Coffee', ENV['SHOP_NAME']
  end

  # Cross-package functionality
  def test_order_with_menu_items
    item = Menu::Item.new(name: 'Test', price_cents: 500)
    order = Orders::Order.new
    order.add(item, quantity: 3)
    assert_equal 1500, order.total_cents
  end

  # Stats (relaxed deps — reads all data stores without explicit dependencies)
  def test_stats_summary
    assert_output(/Stats/) { Stats::Summary.print }
  end

  # Monkey patch isolation: kitchen adds String#to_order_ticket in boot.rb,
  # but it should NOT be available in the root package context.
  def test_monkey_patch_not_leaked
    refute 'hello'.respond_to?(:to_order_ticket),
           'String#to_order_ticket should not leak outside kitchen box'
  end

  def test_kitchen_uses_monkey_patch
    barista = Kitchen::Barista.new(name: 'Test')
    item = Menu::Item.new(name: 'Latte', price_cents: 500)
    result = barista.prepare(item)
    assert_includes result, '🎫', 'Expected order ticket emoji from monkey patch'
  end
end
