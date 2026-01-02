# Boxwerk Example Application

This directory contains a complete example of a Boxwerk application demonstrating strict package isolation and dependency management.

## Architecture

```
example/
├── Gemfile                  # Gem dependencies (money gem)
├── package.yml              # Root package (imports finance)
├── app.rb                   # Application entry point
└── packages/
    ├── finance/
    │   ├── package.yml      # Exports Invoice, TaxCalculator; imports util
    │   └── lib/
    │       ├── invoice.rb
    │       └── tax_calculator.rb
    └── util/
        ├── package.yml      # Exports Calculator, Geometry
        └── lib/
            ├── calculator.rb
            └── geometry.rb
```

## Dependency Graph

```
util (isolated box)
  └── Calculator, Geometry

finance (isolated box) 
  ├── imports: util (Calculator renamed to UtilCalculator)
  └── Invoice, TaxCalculator

root (isolated box)
  ├── imports: finance
  └── Finance::Invoice, Finance::TaxCalculator available
```

## Running the Example

```bash
cd example
RUBY_BOX=1 boxwerk run app.rb
```

**Architecture:**
- Root box: Contains gems (including money gem) and Boxwerk runtime
- Util box: Contains Calculator and Geometry classes
- Finance box: Contains Invoice and TaxCalculator (imports Calculator from Util box as UtilCalculator)
- Root package box: Runs app.rb (imports from Finance box)

**Important:** ALL packages (including root) run in isolated boxes. The main Ruby process only contains gems and the Boxwerk runtime.

### Interactive Console

You can also start an IRB console in the root package context:

```bash
cd example
RUBY_BOX=1 boxwerk console
```

This gives you an interactive session with all imports available (e.g., `Finance::Invoice`).

## What This Demonstrates

### ✓ Strict Isolation
- `Finance::Invoice` and `Finance::TaxCalculator` are accessible (explicit import)
- `Calculator` and `Geometry` are NOT accessible (transitive dependency - not imported)
- `UtilCalculator` is NOT accessible (only available in Finance package's box)
- `Invoice` at top level is NOT accessible (must use `Finance::` namespace)

### ✓ Namespace Control
- Finance package exports are grouped under `Finance::` module
- Import strategies control how dependencies are wired

### ✓ Selective Rename Strategy
- Finance imports `Calculator` from util and renames it to `UtilCalculator`
- This demonstrates the selective rename import strategy

### ✓ Transitive Dependency Blocking
- Root imports Finance
- Finance imports Util
- Root cannot access Util classes (no transitive access)

### ✓ Gem Access
- Money gem is globally accessible in all packages
- Gems from Gemfile are auto-required and available everywhere

### ✓ Clean API Surface
- Each package explicitly declares exports
- Consumers only see what's exported
- Internal implementation details remain hidden

## Package Configuration

### Root Package (`package.yml`)

```yaml
imports:
  - packages/finance  # Default namespace strategy
```

### Finance Package (`packages/finance/package.yml`)

```yaml
exports:
  - Invoice
  - TaxCalculator

imports:
  # Import Calculator from util and rename it to UtilCalculator
  - packages/util:
      Calculator: UtilCalculator
```

### Util Package (`packages/util/package.yml`)

```yaml
exports:
  - Calculator
  - Geometry
```

## Requirements

- Ruby 4.0+ with `Ruby::Box` support
- `RUBY_BOX=1` environment variable must be set
- Boxwerk gem installed or loaded from `../lib`
