# Boxwerk Example

Complete example demonstrating strict package isolation and dependency management.

## Structure

```
example/
├── Gemfile                  # Gem dependencies (money gem)
├── package.yml              # Root package (imports finance)
├── app.rb                   # Entry point
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

**Dependency chain:** root → finance → util

## Running

```bash
cd example
RUBY_BOX=1 boxwerk run app.rb
```

Or use the console (note: currently runs in root box):
```bash
RUBY_BOX=1 boxwerk console
```

## Demonstrates

**Strict isolation:**
- Root accesses `Finance::Invoice` and `Finance::TaxCalculator` (explicit import)
- Root cannot access `Calculator` or `Geometry` (transitive dependency)
- `Invoice` not accessible without `Finance::` namespace

**Import strategies:**
- Root uses default namespace: `packages/finance` → `Finance::`
- Finance uses selective rename: `Calculator` → `UtilCalculator`

**Gem handling:**
- Money gem globally accessible in all packages

**Clean boundaries:**
- Packages export only public API
- Implementation details stay hidden

## Configuration

**Root:** imports `packages/finance` (default namespace)
**Finance:** exports Invoice, TaxCalculator; imports Calculator as UtilCalculator
**Util:** exports Calculator, Geometry
