# Rails Boxwerk Example

Rails application demonstrating Boxwerk runtime package isolation with ActiveRecord models, privacy enforcement, and a foundation package for shared base classes.

## Structure

```
rails/
├── package.yml              # Root (depends on all domain packs)
├── gems.rb                  # Global gems (rails, sqlite3, puma, minitest, rake)
├── global/
│   └── boot.rb              # Boot Rails in global context
├── config/
│   ├── application.rb       # Application config
│   ├── database.yml         # SQLite (dev + test)
│   └── routes.rb            # Placeholder routes
├── Rakefile
├── db/migrate/
│   ├── 001_create_users.rb
│   ├── 002_create_products.rb
│   └── 003_create_orders.rb
├── test/
│   ├── test_helper.rb       # Test DB setup, transaction rollback
│   └── integration_test.rb  # Cross-package integration tests
└── packs/
    ├── foundation/           # ApplicationRecord, ApplicationController
    │   ├── package.yml       # enforce_privacy: true
    │   └── public/
    ├── users/                # User model (public), controller + validator (private)
    │   ├── package.yml       # depends on foundation, public_path: models
    │   ├── boot.rb           # Adds controllers/ and validators/ autoload dirs
    │   ├── models/
    │   ├── controllers/
    │   └── validators/
    ├── products/             # Product model (public), controller + service (private)
    │   ├── package.yml       # depends on foundation, public_path: models
    │   ├── boot.rb           # Adds controllers/ and services/ autoload dirs
    │   ├── models/
    │   ├── controllers/
    │   └── services/
    └── orders/               # Order model (public), controller + service (private)
        ├── package.yml       # depends on foundation, users, products, public_path: models
        ├── boot.rb           # Adds controllers/ and services/ autoload dirs
        ├── models/
        ├── controllers/
        └── services/
```

## Features Demonstrated

- **Rails via global boot** — `global/boot.rb` loads and initializes Rails in the global context; all packs inherit Rails infrastructure
- **Foundation package** — `ApplicationRecord` and `ApplicationController` as public base classes in a leaf package; all domain packs depend on it
- **Rails directory conventions** — Domain packs use `models/`, `controllers/`, `validators/`, `services/` instead of `lib/` and `public/`
- **Custom public_path** — Domain packs set `public_path: models` so model classes are the public API
- **Per-package boot.rb** — Each domain pack uses `boot.rb` to register additional autoload dirs via `Boxwerk.package.autoloader.push_dir`
- **ActiveRecord across boxes** — `Order` belongs_to `:user` and `:product`; associations resolve via `const_missing` across package boundaries
- **Privacy enforcement** — `UserValidator`, `InventoryChecker`, `OrderProcessor` are private to their packs (not in `public_path`)
- **Zeitwerk disabled** — Boxwerk handles autoloading; `config.autoload_paths = []` in the app config

## Boot Sequence

```
1. Global gems loaded in global context (Rails, ActiveRecord, etc.)
2. global/boot.rb runs in global context → requires config/application.rb, Application.initialize!
3. Zeitwerk constants eager-loaded in global context
4. Package boxes created (foundation first, then domain packs)
5. CLI command runs in target package box
```

## Running

```bash
bundle install
bin/boxwerk install
RUBY_BOX=1 bin/boxwerk exec rails server
RUBY_BOX=1 bin/boxwerk exec rails console
RUBY_BOX=1 bin/boxwerk exec rake test
bin/boxwerk info
```
