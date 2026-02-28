# Rails Boxwerk Example

Rails API application demonstrating Boxwerk runtime package isolation with ActiveRecord models, privacy enforcement, and a foundation package for shared base classes.

## Structure

```
rails/
├── package.yml              # Root (depends on all domain packs)
├── Gemfile                  # Global gems (rails, sqlite3, puma, minitest, rake)
├── boot.rb                  # Root package boot — requires config/environment
├── global/
│   └── boot.rb              # Require and eager-load Rails frameworks
├── config/
│   ├── application.rb       # Example::Application config
│   ├── environment.rb       # Standard Rails environment loader
│   ├── database.yml         # SQLite (dev + test)
│   └── routes.rb            # API routes
├── config.ru
├── Rakefile
├── bin/
│   ├── boxwerk              # Boxwerk binstub
│   └── rails                # Rails binstub (sets APP_PATH)
├── db/migrate/
│   ├── 001_create_users.rb
│   ├── 002_create_products.rb
│   └── 003_create_orders.rb
├── test/
│   └── e2e_test.rb          # End-to-end tests
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

- **Rails eager-loaded globally** — `global/boot.rb` requires and eager-loads Rails frameworks so they are inherited by all package boxes
- **Rails initialized in root package** — `boot.rb` requires `config/environment` which initializes the application in the root package box (not the global context)
- **Foundation package** — `ApplicationRecord` and `ApplicationController` as public base classes; all domain packs depend on it
- **Rails directory conventions** — Domain packs use `models/`, `controllers/`, `validators/`, `services/` instead of `lib/` and `public/`
- **Custom public_path** — Domain packs set `public_path: models` so model classes are the public API
- **Per-package boot.rb** — Each domain pack uses `boot.rb` to register additional autoload dirs via `Boxwerk.package.autoloader.push_dir`
- **ActiveRecord across boxes** — `Order` belongs_to `:user` and `:product`; associations resolve via `const_missing` across package boundaries
- **Privacy enforcement** — `UserValidator`, `InventoryChecker`, `OrderProcessor` are private to their packs (not in `public_path`)
- **Zeitwerk disabled** — Boxwerk handles autoloading; `config.autoload_paths = []` in the app config
- **Standard bin/ binstubs** — `bin/rails` sets `APP_PATH` and dispatches via `rails/commands`; no special-casing needed in Boxwerk CLI

## Boot Sequence

```
1. Global gems loaded (Rails, ActiveRecord, etc.)
2. global/boot.rb → require and eager-load Rails frameworks in root box
3. Zeitwerk::Loader.eager_load_all in root box
4. Package boxes created (foundation first, then domain packs, root package last)
5. Root package boot.rb → require config/environment → Application.initialize!
6. CLI command runs in target package box
```

## Running

```bash
bundle install                              # Install global gems
bundle binstubs boxwerk                     # Create bin/boxwerk binstub
bin/boxwerk install                         # Install per-package gems
RUBY_BOX=1 bin/boxwerk exec rails server    # Start server
RUBY_BOX=1 bin/boxwerk exec rails console   # Open console
RUBY_BOX=1 bin/boxwerk exec rake test       # Run tests
bin/boxwerk info                            # Show package graph
```
