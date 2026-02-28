# Rails Boxwerk Example

Rails application demonstrating Boxwerk runtime package isolation with ActiveRecord models, privacy enforcement, and a foundation package for shared base classes.

## Structure

```
rails/
├── package.yml              # Root (depends on all domain packs)
├── gems.rb                  # Global gems (rails, sqlite3, minitest, rake)
├── boot.rb                  # Boot Rails in root box
├── boot/
│   └── rails_app.rb         # RailsApp::Application config (autoloaded)
├── Rakefile
├── app.rb                   # Demo: seed data, test privacy
├── config/
│   ├── database.yml         # SQLite (dev + test)
│   └── routes.rb            # Placeholder routes
├── db/migrate/
│   ├── 001_create_users.rb
│   ├── 002_create_products.rb
│   └── 003_create_orders.rb
├── test/
│   ├── test_helper.rb       # Test DB setup, transaction rollback
│   └── integration_test.rb  # Cross-package integration tests
└── packs/
    ├── foundation/           # ApplicationRecord, ApplicationController
    │   ├── package.yml       # enforce_privacy: true (leaf package)
    │   └── public/
    ├── users/                # User model (public), UserValidator (private)
    │   ├── package.yml       # depends on foundation
    │   └── public/user.rb
    ├── products/             # Product model (public), InventoryChecker (private)
    │   ├── package.yml       # depends on foundation
    │   └── public/product.rb
    └── orders/               # Order model (public), OrderProcessor (private)
        ├── package.yml       # depends on foundation, users, products
        └── public/order.rb
```

## Features Demonstrated

- **Rails in root box** — `boot.rb` initializes Rails; all packs inherit Rails infrastructure
- **Foundation package** — `ApplicationRecord` and `ApplicationController` as public base classes in a leaf package; all domain packs depend on it
- **ActiveRecord across boxes** — `Order` belongs_to `:user` and `:product`; associations resolve via `const_missing` across package boundaries
- **Privacy enforcement** — `UserValidator`, `InventoryChecker`, `OrderProcessor` are private to their packs
- **Zeitwerk disabled** — Boxwerk handles autoloading; `config.autoload_paths = []` in the app config

## Boot Sequence

```
1. Global gems loaded in root box (Rails, ActiveRecord, etc.)
2. boot/ autoloaded → RailsApp::Application defined in root box
3. boot.rb runs → Rails.application.initialize!
4. Package boxes created (foundation first, then domain packs)
5. CLI command runs in target package box
```

## Running

```bash
bundle install
bundle binstubs boxwerk
bin/boxwerk install
RUBY_BOX=1 bin/boxwerk run app.rb
RUBY_BOX=1 bin/boxwerk exec --all rake test
bin/boxwerk info
```
