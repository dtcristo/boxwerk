<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk enforces package boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html) isolation. Each package gets its own `Ruby::Box` — constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

Boxwerk reads standard [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files. No custom configuration format. Packwerk itself is optional — Boxwerk works standalone.

## Goals

Boxwerk shares Packwerk's goal of bringing modular boundaries to Ruby applications:

- **Enforce boundaries at runtime.** Ruby doesn't provide a built-in mechanism for constant-level boundaries between modules. Boxwerk fills this gap using `Ruby::Box` isolation, turning architectural guidelines into runtime guarantees.
- **Enable gradual modularization.** Large applications can adopt packages incrementally. Add `package.yml` files around existing code, declare dependencies, and Boxwerk enforces them. No big-bang rewrite.
- **Feel Ruby-native.** Boxwerk integrates with Bundler, gems.rb, and the standard Ruby toolchain. `bundle exec boxwerk exec rake test` feels like running any other Ruby tool. No custom DSLs or configuration formats.
- **Work standalone.** Boxwerk reads `package.yml` files directly. Packwerk is optional for static analysis at CI time, but not required at runtime.

## Requirements

- Ruby 4.0+ with `RUBY_BOX=1` environment variable
- `package.yml` files ([Packwerk](https://github.com/Shopify/packwerk) format)

## Quick Start

### 1. Add to your gems.rb

```ruby
gem 'boxwerk'
```

### 2. Create packages

```
my_app/
├── gems.rb
├── package.yml              # Root package
├── app.rb
└── packs/
    ├── finance/
    │   ├── package.yml
    │   ├── public/
    │   │   └── invoice.rb   # Public API
    │   └── lib/
    │       └── tax_calc.rb  # Private
    └── util/
        ├── package.yml
        └── lib/
            └── calculator.rb
```

**Root `package.yml`:**
```yaml
enforce_dependencies: true
dependencies:
  - packs/finance
```

**`packs/finance/package.yml`:**
```yaml
enforce_dependencies: true
enforce_privacy: true
dependencies:
  - packs/util
```

### 3. Write your application

```ruby
# app.rb — access dependency constants directly
invoice = Invoice.new(tax_rate: 0.15)
invoice.add_item('Consulting', 100_000)
puts invoice.total

# Direct dependency ✓
Invoice.new

# Transitive dependency ✗ (raises NameError)
Calculator.add(1, 2)
```

### 4. Run

```bash
bundle exec boxwerk run app.rb
```

## CLI

```
boxwerk exec <command> [args...]     Execute a Ruby command in the boxed environment
boxwerk run <script.rb> [args...]    Run a Ruby script in the root box
boxwerk console [irb-args...]        Interactive console in the root box
boxwerk info                         Show package structure and dependencies
boxwerk install                      Run bundle install in all packs with a gems.rb
boxwerk version                      Show version
boxwerk help                         Show usage
```

### Examples

```bash
bundle exec boxwerk run app.rb              # Run a script
bundle exec boxwerk exec rake test          # Run tests with boundary enforcement
bundle exec boxwerk exec rails console      # Start Rails console in boxed environment
bundle exec boxwerk console                 # Interactive IRB in root box
bundle exec boxwerk info                    # Show package graph
```

## Package Configuration

Standard `package.yml` format:

```yaml
# packs/finance/package.yml
enforce_dependencies: true
dependencies:
  - packs/util

# Privacy — only public/ constants are accessible to dependents
enforce_privacy: true
public_path: public/              # default
private_constants:
  - "::InternalHelper"
```

### Per-Package Gems

Packs can have their own `gems.rb` for isolated gem dependencies. Different packs can use different versions of the same gem — each gets its own `$LOAD_PATH`:

```
packs/billing/
├── package.yml
├── gems.rb               # gem 'stripe', '~> 5.0'
├── gems.locked
└── lib/
    └── payment.rb        # require 'stripe' → gets v5
```

Gems in the root `gems.rb` are global — available in all boxes (e.g. `minitest`, `rake`). Per-package gems provide additional isolation on top.

Run `boxwerk install` to install gems for all packs.

### `pack_public: true` Sigil

Files outside the public path can be individually marked public:

```ruby
# pack_public: true
class SpecialService
end
```

## Naming Conventions

File paths within packages follow [Zeitwerk](https://github.com/fxn/zeitwerk) conventions:

- `lib/invoice.rb` → `Invoice`
- `lib/services/billing.rb` → `Services::Billing`
- `public/api.rb` → `Api`

Constants from dependencies are accessible directly — no namespace wrapping.

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- Zeitwerk autoloading doesn't work inside boxes (Boxwerk uses `autoload` directly)
- IRB console runs in root box context with autocomplete disabled

See [FUTURE_IMPROVEMENTS.md](FUTURE_IMPROVEMENTS.md) for plans to address these limitations.

## Examples

See [examples/simple/](examples/simple/) for a working multi-package application with tests.

```bash
cd examples/simple
bundle install
bundle exec boxwerk run app.rb           # Run the example app
bundle exec boxwerk exec rake test       # Run integration tests
```

See [examples/rails/](examples/rails/) for the Rails integration plan.

## Development

```bash
bundle install
RUBY_BOX=1 bundle exec rake test         # Unit + integration tests
RUBY_BOX=1 bundle exec rake e2e          # End-to-end tests
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
