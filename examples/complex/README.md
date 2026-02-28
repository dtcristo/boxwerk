# Complex Boxwerk Example

Coffee shop application demonstrating all Boxwerk features with namespaced constants, per-package gems, privacy enforcement, and unit tests.

## Structure

```
complex/
├── package.yml              # Root (depends on menu, orders, loyalty, kitchen)
├── app.rb                   # Entry point
├── gems.rb                  # Global gems (colorize, dotenv, minitest, rake)
├── .env                     # Environment variables
├── test/
│   └── integration_test.rb  # Cross-package integration tests
└── packs/
    ├── menu/                # enforce_privacy, public_path
    │   ├── public/menu/
    │   │   └── item.rb      # Menu::Item (public)
    │   └── lib/menu/
    │       └── recipe.rb    # Menu::Recipe (private)
    ├── orders/              # enforce_privacy, pack_public sigil
    │   └── lib/orders/
    │       ├── order.rb     # Orders::Order (public via sigil)
    │       └── line_item.rb # Orders::LineItem (private)
    ├── loyalty/             # Per-package faker 2.x
    │   └── lib/loyalty/
    │       └── card.rb      # Loyalty::Card
    └── kitchen/             # Per-package faker 3.x, depends on menu
        └── lib/kitchen/
            └── barista.rb   # Kitchen::Barista
```

## Features Demonstrated

- **Namespaced constants** — `Menu::Item`, `Orders::Order`, etc.
- **Privacy via public_path** — `Menu::Item` is public, `Menu::Recipe` is private
- **Privacy via `pack_public` sigil** — `Orders::Order` marked public in file header
- **Per-package gem isolation** — faker 2.23.0 in loyalty, faker 3.6.0 in kitchen
- **Global gems** — colorize and dotenv accessible in all packages
- **Environment variables** — dotenv loads `.env` across all packages
- **Per-package unit tests** — each pack has its own minitest suite

## Running

```bash
bundle install
bin/boxwerk install
RUBY_BOX=1 bin/boxwerk run app.rb
RUBY_BOX=1 bin/boxwerk exec rake test
RUBY_BOX=1 bin/boxwerk exec --all rake test
bin/boxwerk info
```
