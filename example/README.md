# Boxwerk Example Application

This directory contains a complete example of a Boxwerk application demonstrating strict package isolation and dependency management.

## Architecture

```
example/
├── package.yml              # Root package (imports finance)
├── app.rb                   # Application entry point
└── packages/
    ├── finance/
    │   ├── package.yml      # Exports Invoice, TaxCalculator; imports math
    │   └── lib/
    │       ├── invoice.rb
    │       └── tax_calculator.rb
    └── math/
        ├── package.yml      # Exports MathCalculator
        └── lib/
            └── math_calculator.rb
```

## Dependency Graph

```
math (isolated box)
  └── MathCalculator

finance (isolated box) 
  ├── imports: math
  └── Invoice, TaxCalculator

root (isolated box)
  ├── imports: finance
  └── Finance::Invoice, Finance::TaxCalculator available
```

## Running the Example

```bash
cd example
RUBY_BOX=1 ../exe/boxwerk run app.rb
```

**Architecture:**
- Main box: Gems + Boxwerk runtime only
- Math box: MathCalculator
- Finance box: Invoice, TaxCalculator (imports from Math box)
- Root box: Runs app.rb (imports from Finance box)

**Important:** ALL packages (including root) run in isolated boxes. The main Ruby process only contains gems and the Boxwerk runtime.

### Interactive Console

You can also start an IRB console in the root package context:

```bash
cd example
RUBY_BOX=1 ../exe/boxwerk console
```

This gives you an interactive session with all imports available (e.g., `Finance::Invoice`).

## What This Demonstrates

### ✓ Strict Isolation
- `Finance::Invoice` and `Finance::TaxCalculator` are accessible (explicit import)
- `MathCalculator` is NOT accessible (transitive dependency - not imported)
- `Invoice` at top level is NOT accessible (must use `Finance::` namespace)

### ✓ Namespace Control
- Finance package exports are grouped under `Finance::` module
- Import strategies control how dependencies are wired

### ✓ Transitive Dependency Blocking
- Root imports Finance
- Finance imports Math
- Root cannot access Math (no transitive access)

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
  - packages/math  # Math as namespace
```

### Math Package (`packages/math/package.yml`)

```yaml
exports:
  - MathCalculator
```

## Requirements

- Ruby 4.0+ with `Ruby::Box` support
- `RUBY_BOX=1` environment variable must be set
- Boxwerk gem installed or loaded from `../lib`
