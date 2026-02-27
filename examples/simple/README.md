# Simple Boxwerk Example

Multi-package application demonstrating runtime package isolation with per-package gem version isolation and unit tests.

## Structure

```
simple/
├── Gemfile                  # Global gems (dotenv, minitest, rake)
├── package.yml              # Root package (depends on finance, greeting)
├── app.rb                   # Entry point
├── .env                     # Environment variables (loaded by dotenv)
├── test/
│   └── integration_test.rb  # Integration tests
└── packs/
    ├── finance/
    │   ├── package.yml      # enforce_privacy, depends on util
    │   ├── public/
    │   │   └── invoice.rb   # Public API
    │   └── lib/
    │       ├── line_item.rb      # Private
    │       └── tax_calculator.rb # Private
    ├── greeting/
    │   ├── package.yml
    │   ├── Gemfile          # faker 3.6.0
    │   └── lib/
    │       └── greeting.rb
    └── util/
        ├── package.yml
        ├── Gemfile          # faker 3.5.1
        └── lib/
            ├── calculator.rb
            └── geometry.rb
```

## Dependency Graph

```
$ boxwerk info

boxwerk 0.3.0

Dependency Graph

.
├── packs/finance
│   └── packs/util
└── packs/greeting
```

## Running

From the `examples/simple/` directory:

```bash
bundle install                                        # Install global gems (including boxwerk)
bin/boxwerk install                                   # Install per-package gems
RUBY_BOX=1 bin/boxwerk run app.rb                     # Run the example app
RUBY_BOX=1 bin/boxwerk console                        # Interactive console (root package)
RUBY_BOX=1 bin/boxwerk exec rake test                 # Run root integration tests
RUBY_BOX=1 bin/boxwerk exec -p packs/util rake test   # Run specific package tests
RUBY_BOX=1 bin/boxwerk exec --all rake test           # Run all package tests
bin/boxwerk info                                      # Show package structure
```

> **Note:** The `bin/boxwerk` binstub is pre-configured for this example's `path:`
> gem reference. In your own projects, generate it with `bundle binstubs boxwerk`.

## What It Demonstrates

1. **Direct constant access** — `Invoice` and `Greeting` accessible from root package
2. **Transitive dependency blocking** — `Calculator` blocked (root → finance → util)
3. **Privacy enforcement** — `TaxCalculator` blocked (private, not in `public/`)
4. **Per-package gem version isolation** — faker 3.5.1 in util, 3.6.0 in greeting
5. **Private class instances** — `Invoice#items` returns private `LineItem` objects; methods work but the constant is blocked
6. **Global gems** — dotenv accessible in all packages
7. **Per-package testing** — each pack has its own unit tests run in its own box
