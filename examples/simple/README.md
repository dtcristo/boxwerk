# Simple Boxwerk Example

Multi-package application demonstrating runtime package isolation with per-package gem version isolation and integration tests.

## Structure

```
simple/
├── gems.rb                  # Root dependencies (boxwerk, minitest, rake)
├── package.yml              # Root package (depends on finance, greeting)
├── app.rb                   # Entry point
├── Rakefile                 # Test runner
├── test/
│   └── integration_test.rb  # Integration tests (run in root box)
└── packs/
    ├── finance/
    │   ├── package.yml      # enforce_privacy, depends on util
    │   ├── public/
    │   │   └── invoice.rb   # Public API
    │   └── lib/
    │       └── tax_calculator.rb  # Private (not in public/)
    ├── greeting/
    │   ├── package.yml
    │   ├── gems.rb          # faker 3.6.0
    │   ├── gems.locked
    │   └── lib/
    │       └── greeting.rb  # Uses Faker::Name
    └── util/
        ├── package.yml
        ├── gems.rb          # faker 3.5.1
        ├── gems.locked
        └── lib/
            ├── calculator.rb    # Uses Faker (exposes version)
            └── geometry.rb
```

## Dependency Graph

```
root (.) → finance → util (faker 3.5.1)
         → greeting (faker 3.6.0)
```

## Running

```bash
cd examples/simple
bundle install                           # Install global gems
bundle binstub boxwerk                   # Create bin/boxwerk binstub
bin/boxwerk install                      # Install gems for all packs
bin/boxwerk run app.rb                   # Run the example app
bin/boxwerk exec rake test               # Run integration tests
bin/boxwerk info                         # Show package structure
```

## What It Demonstrates

1. **Direct constant access** — `Invoice` and `Greeting` accessible from root
2. **Transitive dependency blocking** — `Calculator` blocked (root → finance → util)
3. **Privacy enforcement** — `TaxCalculator` blocked (private, not in `public/`)
4. **Per-package gem version isolation** — faker 3.5.1 in util, 3.6.0 in greeting
