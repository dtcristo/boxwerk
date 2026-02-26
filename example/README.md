# Boxwerk Example

Multi-package application demonstrating runtime package isolation.

## Structure

```
example/
├── Gemfile                  # Root gem dependencies
├── packwerk.yml             # Layer definitions (feature > core > utility)
├── package.yml              # Root package (depends on finance, notifications)
├── app.rb                   # Entry point
└── packages/
    ├── finance/
    │   ├── package.yml      # enforce_privacy, layer: core, depends on util
    │   └── lib/
    │       ├── public/
    │       │   └── invoice.rb       # Public API
    │       └── tax_calculator.rb    # Private (not in public_path)
    ├── notifications/
    │   ├── package.yml      # layer: feature; visible_to: ["."]
    │   └── lib/
    │       └── notifier.rb
    └── util/
        ├── package.yml      # layer: utility
        ├── Gemfile          # Per-package gem: json
        ├── Gemfile.lock
        └── lib/
            ├── calculator.rb    # Uses json gem
            └── geometry.rb
```

## Dependency Graph

```
root (.) → finance (core) → util (utility)
root (.) → notifications (feature) → finance (core)
```

## Running

```bash
cd example
bundle install
RUBY_BOX=1 boxwerk run app.rb
```
