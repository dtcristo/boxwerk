# Complex Boxwerk Example

Coffee shop application demonstrating all Boxwerk features with namespaced constants, per-package gems, privacy enforcement, global boot, global data stores, custom autoload dirs, and unit tests.

## Structure

```
complex/
├── package.yml              # Root (depends on menu, orders, loyalty, kitchen)
├── global/
│   ├── boot.rb              # Boot script (runs in global context before packages)
│   └── config.rb            # Config module (autoloaded in global context)
├── main.rb                   # Entry point
├── gems.rb                  # Global gems (colorize, dotenv, minitest, rake)
├── .env                     # Environment variables
├── test/
│   └── integration_test.rb  # Cross-package integration tests
└── packs/
    ├── menu/                # enforce_privacy, public_path, global data store
    │   ├── public/menu/
    │   │   └── item.rb      # Menu::Item (public, sets up Menu.items data store)
    │   └── lib/menu/
    │       └── recipe.rb    # Menu::Recipe (private)
    ├── orders/              # enforce_privacy, pack_public sigil, global data store
    │   └── lib/orders/
    │       ├── order.rb     # Orders::Order (public, sets up Orders.orders data store)
    │       └── line_item.rb # Orders::LineItem (private)
    ├── loyalty/             # Per-package faker 2.x, global data store
    │   └── lib/loyalty/
    │       └── card.rb      # Loyalty::Card (sets up Loyalty.cards data store)
    ├── kitchen/             # Per-package faker 3.x, boot.rb, custom autoload dir
    │   ├── boot.rb          # Adds services/ as autoload dir
    │   ├── services/kitchen/
    │   │   └── prep_service.rb  # Kitchen::PrepService
    │   └── lib/kitchen/
    │       └── barista.rb   # Kitchen::Barista (uses PrepService)
    └── stats/               # Relaxed deps — reads global data stores
        └── lib/stats/
            └── summary.rb   # Stats::Summary (accesses Menu, Orders, Loyalty, Config)
```

## Features Demonstrated

- **Global boot** — `global/boot.rb` loads environment, `global/config.rb` defines global `Config` module
- **Namespaced constants** — `Menu::Item`, `Orders::Order`, etc.
- **Global data stores** — each module has a class-level array (`Menu.items`, `Orders.orders`, `Loyalty.cards`) for tracking instances
- **Privacy via public_path** — `Menu::Item` is public, `Menu::Recipe` is private
- **Privacy via `pack_public` sigil** — `Orders::Order` marked public in file header
- **Per-package gem isolation** — faker 2.23.0 in loyalty, faker 3.6.0 in kitchen
- **Custom autoload dirs** — kitchen's `boot.rb` adds `services/` via `BOXWERK_CONFIG[:autoload_dirs]`
- **Global gems** — colorize accessible in all packages
- **Global config** — `Config::CURRENCY` defined in global/ and used across packages
- **Relaxed deps** — stats reads global data stores from other modules without declaring dependencies
- **Per-package unit tests** — each pack has its own minitest suite

## Running

```bash
bundle install
bin/boxwerk install
RUBY_BOX=1 bin/boxwerk run main.rb
RUBY_BOX=1 bin/boxwerk exec rake test
RUBY_BOX=1 bin/boxwerk exec --all rake test
bin/boxwerk info
```
