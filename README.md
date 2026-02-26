<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk enforces package boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html) isolation. Each package gets its own `Ruby::Box` — constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

Boxwerk reads standard [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files. No custom configuration format. Packwerk itself is optional — Boxwerk works standalone.

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
    │   └── lib/
    │       └── invoice.rb
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
dependencies:
  - packs/util
```

### 3. Write your application

```ruby
# app.rb — access dependency constants directly
invoice = Invoice.new(10_000)
puts invoice.total

# Direct dependency ✓
Invoice.new

# Transitive dependency ✗ (raises NameError)
Calculator.add(1, 2)
```

### 4. Run

```bash
RUBY_BOX=1 boxwerk run app.rb
```

## CLI

```
boxwerk run <script.rb> [args...]    Run a script with package isolation
boxwerk console [irb-args...]        Interactive console in root package context
boxwerk info                         Show package structure and dependencies
boxwerk install                      Run bundle install in all packs with a Gemfile
boxwerk version                      Show version
boxwerk help                         Show usage
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

Packs can have their own `gems.rb` (or `Gemfile`) for isolated gem dependencies. Different packs can use different versions of the same gem.

```
packs/billing/
├── package.yml
├── gems.rb               # gem 'stripe', '~> 5.0'
├── gems.locked
└── lib/
    └── payment.rb        # require 'stripe' → gets v5
```

Run `boxwerk install` to install gems for all packs, or `bundle install` in individual pack directories.

### `pack_public: true` Sigil

Files outside the public path can be individually marked public:

```ruby
# pack_public: true
class SpecialService
end
```

## Naming Conventions

File paths within packages follow [Zeitwerk](https://github.com/fxn/zeitwerk) conventions for autoloading:

- `lib/invoice.rb` → `Invoice`
- `lib/services/billing.rb` → `Services::Billing`

Constants from dependencies are accessible directly — no namespace wrapping.

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- Zeitwerk autoloading doesn't work inside boxes (Boxwerk uses `autoload` directly)
- IRB console runs in root box context with autocomplete disabled

## Examples

See [examples/simple/](examples/simple/) for a working multi-package application.

```bash
cd examples/simple && bundle install && RUBY_BOX=1 boxwerk run app.rb
```

See [examples/rails/](examples/rails/) for the Rails integration plan.

## Development

```bash
bundle install
RUBY_BOX=1 bundle exec rake test
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
