# Simple Boxwerk Example

Multi-package application demonstrating runtime package isolation with per-package gem version isolation and unit tests.

## Structure

```
simple/
├── gems.rb                  # Root dependencies (minitest, rake)
├── package.yml              # Root package (depends on finance, greeting)
├── app.rb                   # Entry point
├── Rakefile                 # Root test runner
├── test/
│   └── integration_test.rb  # Integration tests (run in root package box)
└── packs/
    ├── finance/
    │   ├── package.yml      # enforce_privacy, depends on util
    │   ├── Rakefile         # Finance test runner
    │   ├── public/
    │   │   └── invoice.rb   # Public API
    │   ├── lib/
    │   │   └── tax_calculator.rb  # Private (not in public/)
    │   └── test/
    │       └── invoice_test.rb    # Unit tests
    ├── greeting/
    │   ├── package.yml
    │   ├── Rakefile         # Greeting test runner
    │   ├── gems.rb          # faker 3.6.0
    │   ├── gems.locked
    │   ├── lib/
    │   │   └── greeting.rb  # Uses Faker::Name
    │   └── test/
    │       └── greeting_test.rb   # Unit tests
    └── util/
        ├── package.yml
        ├── Rakefile         # Util test runner
        ├── gems.rb          # faker 3.5.1
        ├── gems.locked
        ├── lib/
        │   ├── calculator.rb    # Uses Faker (exposes version)
        │   └── geometry.rb
        └── test/
            ├── calculator_test.rb  # Unit tests
            └── geometry_test.rb
```

## Dependency Graph

```
root (.) → finance → util (faker 3.5.1)
         → greeting (faker 3.6.0)
```

## Running

```bash
gem install boxwerk
RUBY_BOX=1 boxwerk install                         # Install gems for all packages
RUBY_BOX=1 boxwerk run app.rb                      # Run the example app
RUBY_BOX=1 boxwerk exec rake test                  # Run root integration tests
RUBY_BOX=1 boxwerk exec -p packs/util rake test    # Run specific package unit tests
RUBY_BOX=1 boxwerk exec --all rake test            # Run all package tests
RUBY_BOX=1 boxwerk info                            # Show package structure
```

## What It Demonstrates

1. **Direct constant access** — `Invoice` and `Greeting` accessible from root
2. **Transitive dependency blocking** — `Calculator` blocked (root → finance → util)
3. **Privacy enforcement** — `TaxCalculator` blocked (private, not in `public/`)
4. **Per-package gem version isolation** — faker 3.5.1 in util, 3.6.0 in greeting
5. **Per-package testing** — each pack has its own unit tests run in its own box
