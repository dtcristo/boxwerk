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
    │       └── tax_calculator.rb  # Private
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
. (root)
├── packs/finance
│   └── packs/util
└── packs/greeting
```

## Running

```bash
gem install boxwerk
boxwerk install                                    # Install gems for all packages
RUBY_BOX=1 boxwerk run app.rb                      # Run the example app
RUBY_BOX=1 boxwerk exec rake test                  # Run root package integration tests
RUBY_BOX=1 boxwerk exec -p packs/util rake test    # Run specific package unit tests
RUBY_BOX=1 boxwerk exec --all rake test            # Run all package tests
RUBY_BOX=1 boxwerk info                            # Show package structure
```

## What It Demonstrates

1. **Direct constant access** — `Invoice` and `Greeting` accessible from root package
2. **Transitive dependency blocking** — `Calculator` blocked (root → finance → util)
3. **Privacy enforcement** — `TaxCalculator` blocked (private, not in `public/`)
4. **Per-package gem version isolation** — faker 3.5.1 in util, 3.6.0 in greeting
5. **Global gems** — dotenv accessible in all packages
6. **Per-package testing** — each pack has its own unit tests run in its own box
