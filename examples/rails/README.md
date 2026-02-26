# Rails + Boxwerk Example

> **Status:** Planned — this directory will contain a working Rails application
> with Boxwerk runtime package isolation.

## Goal

Demonstrate how Boxwerk enforces package boundaries in a Rails application at
runtime. Rails itself and its core dependencies remain in the global context,
while application code is isolated into packages using `Ruby::Box`.

## Proposed Structure

```
rails/
├── gems.rb                          # Rails + shared gems
├── gems.locked
├── package.yml                      # Root package
├── Rakefile
├── config/
│   ├── application.rb               # Rails::Application (not boxed)
│   ├── database.yml
│   ├── routes.rb                    # Draws routes from all packs
│   ├── environments/
│   │   ├── development.rb
│   │   ├── test.rb
│   │   └── production.rb
│   └── initializers/
│       └── boxwerk.rb               # Boots Boxwerk after Rails init
├── db/
│   ├── migrate/
│   │   ├── 001_create_users.rb
│   │   ├── 002_create_products.rb
│   │   └── 003_create_orders.rb
│   └── schema.rb
├── app/
│   ├── controllers/
│   │   └── application_controller.rb
│   └── views/
│       └── layouts/
│           └── application.html.erb
└── packs/
    ├── users/
    │   ├── package.yml              # enforce_privacy: true
    │   ├── public/
    │   │   └── user.rb              # Public: User model
    │   ├── lib/
    │   │   ├── user_service.rb      # Private: internal logic
    │   │   └── password_hasher.rb   # Private: internal logic
    │   ├── app/
    │   │   └── controllers/
    │   │       └── users_controller.rb
    │   └── test/
    │       └── user_test.rb
    ├── products/
    │   ├── package.yml              # enforce_privacy: true
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
        ├── package.yml              # depends on users, products
        ├── public/
        │   └── order.rb             # Public: Order model
        ├── lib/
        │   └── order_processor.rb   # Uses User and Product
        ├── app/
        │   └── controllers/
        │       └── orders_controller.rb
        └── test/
            └── order_test.rb
```

## Package Dependency Graph

```
orders → users
orders → products
```

Users and products have no dependencies on each other. Orders depends on both.

## Implementation Plan

### Phase 1: Basic Rails App with Packages

1. **Generate a minimal Rails app** using `rails new` with `--minimal` flag
   (skip Action Mailer, Action Cable, Active Storage, etc.)

2. **Create `package.yml` files** for root and each pack following standard
   Packwerk conventions.

3. **Move models to pack `public/` directories** so they serve as public APIs.
   Internal service classes go in `lib/`.

4. **Configure Boxwerk initializer** (`config/initializers/boxwerk.rb`):
   ```ruby
   # Boot Boxwerk after Rails has initialized
   Rails.application.config.after_initialize do
     if defined?(Ruby::Box) && Ruby::Box.enabled?
       Boxwerk::Setup.run!
     end
   end
   ```

### Phase 2: ActiveRecord Integration

5. **Cross-pack model associations** — Orders pack needs `User` and `Product`
   models. With no-namespace resolution, `belongs_to :user` will resolve
   `User` from the users pack automatically.

6. **Database migrations** stay in the root `db/migrate/` directory (standard
   Rails convention). Each pack's models use the shared database connection.

7. **Verify ActiveRecord works across boxes** — test that associations,
   queries, and callbacks function correctly when models are in different
   boxes.

### Phase 3: Controllers and Routes

8. **Pack controllers** inherit from `ApplicationController` (in root).
   They access models from their declared dependencies.

9. **Route drawing** — `config/routes.rb` draws routes from all packs.
   Each pack can contribute routes via a conventional file:
   ```ruby
   # config/routes.rb
   Rails.application.routes.draw do
     resources :users
     resources :products
     resources :orders
   end
   ```

10. **Verify request/response cycle** — test that HTTP requests route to pack
    controllers, which access pack models, and return correct responses.

### Phase 4: Privacy Enforcement

11. **Privacy in action** — demonstrate that a controller in the orders pack
    can access `User` and `Product` (public), but cannot access
    `PasswordHasher` or `InventoryChecker` (private).

12. **Error handling** — show descriptive `NameError` messages when privacy
    is violated, helping developers understand package boundaries.

### Phase 5: Testing

13. **Per-pack tests** — each pack has its own test directory. Tests run in
    the pack's box context, ensuring the pack works with only its declared
    dependencies.

14. **Integration tests** — verify the full Rails request cycle with Boxwerk
    isolation enabled.

## Key Challenges

### ActiveRecord and Cross-Box Constants

ActiveRecord associations (`belongs_to`, `has_many`) resolve constant names
to find associated models. With Boxwerk:
- The `orders` box must be able to resolve `User` (from users pack)
- This works naturally with no-namespace resolution — `User` is found by
  searching dependency boxes

### Zeitwerk Compatibility

Rails uses Zeitwerk for autoloading. Inside `Ruby::Box`, Zeitwerk's global
`Module#const_missing` hook doesn't fire. Boxwerk's own autoloading handles
this, but Rails' reloading features won't work. This is a known limitation.

**Workaround:** Use `config.eager_load = true` in development to load all
code at boot time, matching production behavior.

### Middleware and Initializers

Rails middleware and initializers assume a global namespace. They run outside
of any box and aren't affected by Boxwerk isolation. This is the desired
behavior — Rails infrastructure stays global, application code gets isolated.

### Console and Development

`rails console` can be wrapped with Boxwerk:
```bash
RUBY_BOX=1 boxwerk console
```

This gives an IRB session in the root box context with all packages wired.

## Prerequisites

- Ruby 4.0+ with `Ruby::Box` support
- Rails 8.0+ (or latest stable)
- RUBY_BOX=1 environment variable
