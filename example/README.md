# Boxwerk Example

Complete example demonstrating runtime package isolation using Packwerk's dependency
declarations and Ruby::Box enforcement — including privacy, visibility, layers, and gem isolation.

## Structure

```
example/
├── Gemfile                  # Gem dependencies (money gem)
├── packwerk.yml             # Layer definitions (feature > core > utility)
├── package.yml              # Root package (depends on finance, notifications)
├── app.rb                   # Entry point
└── packages/
    ├── finance/
    │   ├── package.yml      # Depends on util; enforce_privacy + layer: core
    │   └── lib/
    │       ├── public/
    │       │   └── invoice.rb       # Public API
    │       ├── invoice.rb
    │       └── tax_calculator.rb    # Private (not in public_path)
    ├── notifications/
    │   ├── package.yml      # layer: feature; visible_to: ["."]
    │   └── lib/
    │       └── notifier.rb
    └── util/
        ├── package.yml      # No dependencies; layer: utility
        └── lib/
            ├── calculator.rb
            └── geometry.rb
```

## Dependency Graph

```
root (.) → finance (core) → util (utility)
root (.) → notifications (feature) → finance (core)
```

## Features Demonstrated

### Privacy enforcement
- Finance has `enforce_privacy: true` with `public_path: lib/public/`
- `Finance::Invoice` is accessible (in public path)
- `Finance::TaxCalculator` is blocked (private, not in public path)

### Visibility enforcement
- Notifications has `enforce_visibility: true` with `visible_to: ["."]`
- Only the root package can access `Notifications::Notifier`

### Layer enforcement
- Layers: `feature > core > utility` (defined in `packwerk.yml`)
- Notifications (feature) → Finance (core) ✓
- Finance (core) → Util (utility) ✓
- Utility → Feature would raise `LayerViolationError` at boot ✗

### Namespace isolation
- Root accesses `Finance::Invoice` and `Notifications::Notifier` (declared dependencies)
- Root cannot access `Util::Calculator` (transitive, not declared)
- `Invoice` not accessible without `Finance::` namespace

### Global gem access
- Money gem globally accessible in all packages

## Running

```bash
cd example
bundle install
RUBY_BOX=1 boxwerk run app.rb
```

Or use the console:
```bash
RUBY_BOX=1 boxwerk console
```
