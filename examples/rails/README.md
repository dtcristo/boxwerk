# Rails + Boxwerk Example

> **Status:** Planned — this directory will contain a working Rails application
> with Boxwerk runtime package isolation.

## Goal

Demonstrate how Boxwerk enforces package boundaries in a Rails application at
runtime. Rails and its core dependencies live in the root box as global gems.
Application code is isolated into packages using `Ruby::Box`. A `foundation`
package provides base classes (`ApplicationRecord`, `ApplicationController`)
that all packs depend on.

## Proposed Structure

```
rails/
├── package.yml                      # Root package (depends on all packs)
├── gems.rb                          # Rails + shared gems
├── gems.locked
├── boot.rb                          # Boot Rails in root box
├── boot/
│   └── rails_config.rb              # Rails::Application configuration
├── Rakefile
├── config/
│   ├── database.yml
│   ├── routes.rb                    # Draws routes from all packs
│   ├── environments/
│   │   ├── development.rb
│   │   ├── test.rb
│   │   └── production.rb
│   └── initializers/
│       └── ...                      # Standard Rails initializers
├── db/
│   ├── migrate/
│   │   ├── 001_create_users.rb
│   │   ├── 002_create_products.rb
│   │   └── 003_create_orders.rb
│   └── schema.rb
└── packs/
    ├── foundation/
    │   ├── package.yml              # No dependencies (leaf package)
    │   └── public/
    │       ├── application_record.rb
    │       └── application_controller.rb
    ├── users/
    │   ├── package.yml              # depends on foundation
    │   ├── public/
    │   │   └── user.rb              # Public: User model
    │   ├── lib/
    │   │   ├── user_service.rb      # Private
    │   │   └── password_hasher.rb   # Private
    │   ├── app/
    │   │   └── controllers/
    │   │       └── users_controller.rb
    │   └── test/
    │       └── user_test.rb
    ├── products/
    │   ├── package.yml              # depends on foundation
    │   ├── public/
    │   │   └── product.rb           # Public: Product model
    │   ├── lib/
    │   │   └── inventory_checker.rb # Private
    │   ├── app/
    │   │   └── controllers/
    │   │       └── products_controller.rb
    │   └── test/
    │       └── product_test.rb
    └── orders/
        ├── package.yml              # depends on foundation, users, products
        ├── public/
        │   └── order.rb             # Public: Order model
        ├── lib/
        │   └── order_processor.rb   # Private
        ├── app/
        │   └── controllers/
        │       └── orders_controller.rb
        └── test/
            └── order_test.rb
```

## Package Dependency Graph

```
.
├── packs/foundation          (no deps — leaf package)
├── packs/users               → foundation
├── packs/products            → foundation
└── packs/orders              → foundation, users, products
```

## Boot Sequence

Boxwerk's boot sequence for a Rails app:

```
1. exe/boxwerk starts, re-execs out of Bundler if needed
2. Switch to root box
3. Load boxwerk gem, run Bundler.setup + Bundler.require
   → Rails gem loaded in root box
4. Boxwerk::Setup.run:
   a. Find root package.yml
   b. Scan boot/ directory → autoload RailsConfig in root box
   c. Run boot.rb → boots Rails (Rails.application.initialize!)
   d. Create package boxes (foundation first, then others)
   e. Wire dependency constants
5. CLI command runs in target package box
```

### boot.rb

```ruby
# boot.rb — runs in root box after gems, before package boxes
require 'rails'
require_relative 'boot/rails_config'

# Initialize Rails (creates the application, loads config)
Rails.application.initialize!
```

### boot/rails_config.rb

```ruby
# boot/rails_config.rb — autoloaded in root box
module RailsConfig
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = true  # Required: Zeitwerk reloading won't work in boxes
    config.api_only = true    # Example uses API-only mode
  end
end
```

Rails initializers (`config/initializers/*.rb`) are loaded by Rails during
`initialize!`, which happens in the root box. This means all initializer
code runs in the root box context — correct behaviour since initializers
configure global Rails infrastructure.

## Foundation Package

The `foundation` package is a leaf package (no dependencies) that provides
base classes all packs inherit from:

```ruby
# packs/foundation/public/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
```

```ruby
# packs/foundation/public/application_controller.rb
class ApplicationController < ActionController::API
end
```

Every pack that defines models or controllers declares a dependency on
`packs/foundation`:

```yaml
# packs/users/package.yml
enforce_dependencies: true
enforce_privacy: true
dependencies:
  - packs/foundation
```

### Why a Package (Not boot/)

Base classes like `ApplicationRecord` are placed in a dedicated package
rather than `boot/` so that:

- **Dependencies are explicit.** Each pack declares it needs foundation
  classes. This is visible in `package.yml` and `boxwerk info`.
- **Privacy works.** The foundation package uses `public/` to control
  which base classes are available.
- **Testable in isolation.** The foundation package can have its own tests.
- **Consistent pattern.** All application code lives in packages. `boot/`
  is reserved for infrastructure/configuration that isn't application code.

## Database Migrations

Migrations live in the root `db/migrate/` directory (standard Rails
convention). All packs share the same database connection — ActiveRecord
is a global gem configured in the root box.

```ruby
# db/migrate/001_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
    end
  end
end
```

Migrations run via `boxwerk exec rake db:migrate` in the root box context.
No package isolation needed for schema changes.

## ActiveRecord Across Boxes

Cross-pack model associations work naturally with Boxwerk's constant
resolution:

```ruby
# packs/orders/public/order.rb
class Order < ApplicationRecord        # ← from foundation (dependency)
  belongs_to :user                     # ← resolves User from users pack
  belongs_to :product                  # ← resolves Product from products pack
end
```

ActiveRecord resolves association class names via `const_get`, which triggers
`const_missing` in the box. Boxwerk's dependency resolver finds `User` in
the users pack and returns it. No namespacing needed.

## Controllers and Routes

Pack controllers inherit from `ApplicationController` (via foundation) and
are autoloaded in their pack's box:

```ruby
# packs/users/app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    render json: User.all
  end
end
```

Routes are defined in `config/routes.rb` which Rails loads in the root box.
The root box has a composite resolver that can access all pack constants:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :users
  resources :products
  resources :orders
end
```

**Challenge:** Rails' router resolves controller constants. These must be
accessible from the root box. Boxwerk's root box resolver (installed for
`exec`/`run` commands) handles this — it searches the target package's box
and its dependencies.

## Zeitwerk Considerations

Rails normally uses Zeitwerk for autoloading. With Boxwerk:

- **Boxwerk replaces Zeitwerk's autoloading role.** Boxwerk scans package
  directories using Zeitwerk's inflector and file scanner, then registers
  autoloads directly in each box. Rails' own Zeitwerk loader is disabled
  for pack code.
- **No reloading.** Zeitwerk's reloading depends on `const_added` callbacks
  that don't cross box boundaries. Use `config.eager_load = true` in all
  environments. Restart for code changes.
- **Inflection rules carry over.** Boxwerk uses Zeitwerk's inflector, so
  acronyms (`HTML`, `API`) work the same way.
- **Rails autoloaders for non-pack code.** `boot/` and `config/` code is
  loaded in the root box where Rails' own Zeitwerk loader works normally.
  Only pack code uses Boxwerk's autoloading.

## Running

```bash
# Setup
bundle install
bundle binstubs boxwerk
bin/boxwerk install

# Development
RUBY_BOX=1 bin/boxwerk exec rails server
RUBY_BOX=1 bin/boxwerk exec rails console
RUBY_BOX=1 bin/boxwerk exec rake db:migrate

# Testing
RUBY_BOX=1 bin/boxwerk exec --all rake test
RUBY_BOX=1 bin/boxwerk exec -p packs/orders rake test

# Info
bin/boxwerk info
```

## Key Challenges

### Request Dispatch Across Boxes

When a Rails request comes in, the router (root box) dispatches to a
controller. That controller lives in a package box. The request must
cross the box boundary:

- Option A: Router resolves the controller constant via root box resolver,
  then the controller's methods execute in their defining box (file scope
  rule of Ruby::Box).
- Option B: Wrap the dispatch in `box.eval` to ensure full box context.

File scope rule should handle this naturally — methods defined in a pack's
controller file execute in that pack's box regardless of caller.

### Middleware Stack

Rails middleware runs in the root box. Middleware that touches application
constants (e.g., authentication checking `User`) needs access to pack
constants. The root box resolver provides this.

### Asset Pipeline / Views

Views and assets are global Rails concerns, not isolated into boxes.
They live in the root or in pack `app/views/` directories. ERB templates
execute in controller context (the pack's box), so pack constants are
accessible in views rendered by pack controllers.

### Console

```bash
RUBY_BOX=1 bin/boxwerk console
```

Provides an IRB session with all pack constants accessible via the root box
composite resolver. `User.all`, `Order.count` etc. work as expected.

## Prerequisites

- Ruby 4.0+ with `Ruby::Box` support (`RUBY_BOX=1`)
- Rails 8.0+
- Boxwerk gem
