<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk enforces package boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) isolation. Each package gets its own `Ruby::Box` — constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

Boxwerk reads standard [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files. No custom configuration format. Packwerk itself is optional — Boxwerk works standalone.

## Goals

Boxwerk shares Packwerk's goal of bringing modular boundaries to Ruby applications:

- **Enforce boundaries at runtime.** Ruby doesn't provide a built-in mechanism for constant-level boundaries between modules. Boxwerk fills this gap using `Ruby::Box` isolation, turning architectural guidelines into runtime guarantees.
- **Enable gradual modularization.** Large applications can adopt packages incrementally. Add `package.yml` files around existing code, declare dependencies, and Boxwerk enforces them. No big-bang rewrite.
- **Feel Ruby-native.** Boxwerk integrates with Bundler, `Gemfile`/`gems.rb`, and the standard Ruby toolchain. `boxwerk exec rake test` feels like running any other Ruby tool. No custom DSLs or configuration formats.
- **Work standalone.** Boxwerk reads `package.yml` files directly. Packwerk is optional for static analysis at CI time, but not required at runtime.

## Ruby::Box

[`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) provides in-process isolation of classes, modules, and constants. Key behaviours relevant to Boxwerk:

- **Box creation.** `Ruby::Box.new` creates a user box copied from the root box. All user boxes are flat — there is no nesting.
- **File scope.** One `.rb` file runs in a single box. Methods and procs defined in that file always execute in that file's box.
- **Top-level constants.** Constants defined at the top level are constants of `Object` within that box. `box::Foo` accesses them from outside.
- **Monkey patch isolation.** Reopened built-in classes (e.g. adding `String#blank?`) are visible only within the box that defined them.
- **Global variable isolation.** `$LOAD_PATH`, `$LOADED_FEATURES`, and other globals are isolated per box.
- **Enabling.** Set `RUBY_BOX=1` before starting Ruby. It cannot be enabled after process boot.

See the [official Ruby::Box documentation](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) for full details and known issues.

## Requirements

- Ruby 4.0+ with `RUBY_BOX=1` environment variable
- `package.yml` files ([Packwerk](https://github.com/Shopify/packwerk) format)

## Quick Start

### 1. Install Boxwerk

```bash
gem install boxwerk
```

### 2. Add a `Gemfile` for your project

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'minitest'
gem 'rake'
```

### 3. Create packages

```
my_app/
├── Gemfile
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

### 4. Write your application

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

### 5. Install and run

```bash
boxwerk install                  # Bundle install for all packages
RUBY_BOX=1 boxwerk run app.rb    # Run with package isolation
```

## CLI

```
boxwerk exec <command> [args...]     Execute a command in the boxed environment
boxwerk run <script.rb> [args...]    Run a Ruby script in a package box
boxwerk console [irb-args...]        Interactive console in a package box
boxwerk info                         Show package structure and dependencies
boxwerk install                      Install gems for all packages
boxwerk version                      Show version
boxwerk help                         Show usage
```

### Options

```
-p, --package <name>         Run in a specific package box (default: root)
    --all                    Run exec for all packages sequentially
    --root-box, -r           Run in the root box (no package context)
```

> **Root package vs root box:** The root package (`.`) is your top-level
> `package.yml` — it gets its own box like any other package. The root box
> (`Ruby::Box.root`) is where global gems are loaded; it has no package
> constants. Use `--root-box` for debugging gem loading.

### Examples

```bash
boxwerk run app.rb                          # Run a script
boxwerk exec rake test                      # Run tests (root package)
boxwerk exec -p packs/util rake test        # Run tests for a specific package
boxwerk exec --all rake test                # Run tests for all packages
boxwerk console                             # Interactive IRB (root package)
boxwerk console -p packs/finance            # IRB in a specific package
boxwerk console --root-box                  # IRB in the root box (debugging)
boxwerk info                                # Show package graph
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

Packages can have their own `Gemfile` for isolated gem dependencies. Different packages can use different versions of the same gem — each gets its own `$LOAD_PATH`:

```
packs/billing/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 5.0'
├── Gemfile.lock
└── lib/
    └── payment.rb        # require 'stripe' → gets v5
```

Gems in the root `Gemfile` are global — available in all boxes via root box inheritance. Per-package gems provide additional isolation on top.

Run `boxwerk install` to install gems for all packages.

### `pack_public: true` Sigil

Files outside the public path can be individually marked public:

```ruby
# pack_public: true
class SpecialService
end
```

## Architecture

Boxwerk is designed to be installed globally (`gem install boxwerk`) rather than via Bundler. This ensures gems are loaded exactly once — in the root box — and inherited by all package boxes.

See [ARCHITECTURE.md](ARCHITECTURE.md) for full implementation details including the boot sequence, constant resolution, and Ruby::Box internals.

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- Boxwerk uses `autoload` directly (not Zeitwerk) inside boxes
- IRB autocomplete disabled in console (box-scoped constants not visible to completer)

See [TODO.md](TODO.md) for plans to address these limitations.

## Examples

- See [examples/simple/](examples/simple/) for a working multi-package application with per-package tests and gem version isolation.
- See [examples/rails/](examples/rails/) for the Rails integration plan.

## Development

```bash
bundle install
rake install                              # Build and install boxwerk gem
RUBY_BOX=1 bundle exec rake test          # Unit + integration tests
RUBY_BOX=1 bundle exec rake e2e           # End-to-end tests
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
