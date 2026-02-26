<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk is the **runtime enforcement companion** to [Packwerk](https://github.com/Shopify/packwerk). While Packwerk catches dependency violations at CI time through static analysis, Boxwerk enforces those same boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html) isolation.

Each package gets its own `Ruby::Box`. Dependencies are exposed via namespace proxies — constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

Boxwerk reads standard [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files and [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) config keys. No custom configuration format.

## Requirements

- Ruby 4.0.1+ with `RUBY_BOX=1` environment variable
- [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files

## Quick Start

### 1. Add to your Gemfile

```ruby
gem 'boxwerk'
```

### 2. Create packages with Packwerk format

```
my_app/
├── Gemfile
├── package.yml              # Root package
├── app.rb
└── packages/
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
  - packages/finance
```

**`packages/finance/package.yml`:**
```yaml
enforce_dependencies: true
dependencies:
  - packages/util
```

### 3. Write your application

```ruby
# app.rb — access dependencies via namespace derived from package path
invoice = Finance::Invoice.new(10_000)
puts invoice.total

# Direct dependency ✓
Finance::Invoice.new

# Transitive dependency ✗ (raises NameError)
Util::Calculator.add(1, 2)
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
boxwerk version                      Show version
boxwerk help                         Show usage
```

## Package Configuration

Standard Packwerk `package.yml` with [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) keys:

```yaml
# packages/finance/package.yml
enforce_dependencies: true
dependencies:
  - packages/util

# Privacy — only public_path constants are accessible to dependents
enforce_privacy: true
public_path: app/public/          # default
private_constants:
  - "::Finance::InternalHelper"

# Visibility — restrict which packages can see this one
enforce_visibility: true
visible_to:
  - packages/billing
  - .

# Folder privacy — only sibling/parent packages can access
enforce_folder_privacy: true

# Layers — prevent lower layers from depending on higher ones
enforce_layers: true
layer: core
```

Layer order is defined in `packwerk.yml`:

```yaml
layers:
  - feature     # highest
  - core
  - utility     # lowest
```

### Per-Package Gems

Packages can have their own `Gemfile` (or `gems.rb`) for isolated gem dependencies. Different packages can use different versions of the same gem.

```
packages/billing/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 5.0'
├── Gemfile.lock
└── lib/
    └── payment.rb        # require 'stripe' → gets v5
```

Run `bundle install` in the package directory to generate the lockfile. Boxwerk resolves gem paths at boot via Bundler.

### `pack_public: true` Sigil

Files outside the public path can be individually marked public:

```ruby
# pack_public: true
class SpecialService
end
```

## Naming Conventions

Package paths map to namespaces using [Zeitwerk](https://github.com/fxn/zeitwerk) conventions:

- `packages/finance` → `Finance`
- `packages/tax_calc` → `TaxCalc`

File paths within packages follow the same conventions for autoloading.

## Complementary Tools

| Tool | Role |
|------|------|
| [Packwerk](https://github.com/Shopify/packwerk) | Static analysis at CI time (`packwerk check`) |
| [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) | Privacy, visibility, layers config |
| [Packs](https://github.com/rubyatscale/packs) | CLI for managing package structure |
| **Boxwerk** | Runtime enforcement via `Ruby::Box` |

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- Zeitwerk autoloading doesn't work inside boxes (Boxwerk uses `autoload` directly)
- IRB console runs in root box context with autocomplete disabled

## Example

See [example/](example/) for a working multi-package application.

```bash
cd example && bundle install && RUBY_BOX=1 boxwerk run app.rb
```

## Development

```bash
bundle install
RUBY_BOX=1 bundle exec rake test
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
