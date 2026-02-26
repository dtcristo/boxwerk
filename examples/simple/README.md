# Simple Boxwerk Example

Multi-package application demonstrating runtime package isolation.

## Structure

```
simple/
├── gems.rb                  # Root gem dependencies
├── package.yml              # Root package (depends on finance)
├── app.rb                   # Entry point
└── packs/
    ├── finance/
    │   ├── package.yml      # enforce_privacy, depends on util
    │   ├── public/
    │   │   └── invoice.rb   # Public API
    │   └── lib/
    │       └── tax_calculator.rb    # Private (not in public/)
    └── util/
        ├── package.yml
        ├── gems.rb          # Per-package gem: json
        ├── gems.locked
        └── lib/
            ├── calculator.rb    # Uses json gem
            └── geometry.rb
```

## Dependency Graph

```
root (.) → finance → util
```

## Running

```bash
cd examples/simple
bundle install
RUBY_BOX=1 boxwerk run app.rb
```
