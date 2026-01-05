# Boxwerk

Boxwerk is an **experimental** Ruby package system with Box-powered constant isolation. It organizes code into packages with explicit dependencies and strict constant access using Ruby 4.0 [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html). Inspired by [Packwerk](https://github.com/Shopify/packwerk).

## Features

- **Strict Isolation**: Each package runs in its own `Ruby::Box`, preventing constants from leaking without explicit imports or exports.
- **Explicit Dependencies**: Dependencies are declared in `package.yml` files, forming a DAG.
- **Ergonomic Imports**: Flexible import strategies (namespaced, aliased, selective, renamed).

## Limtations

- There is no isolation of gems.
- Gems are required to be eager loaded in the root box to be accessible in packages.
- No support for reloading of constants.
- Exported constants must follow Zeitwerk naming conventions for their source location.

## Requirements

- Ruby 4.0+ with `RUBY_BOX=1` environment variable must be set.

## Quick Start

### 1. Create a Package Structure

```
my_app/
├── Gemfile
├── package.yml              # Root package manifest
├── app.rb                   # Your application entrypoint
└── packages/
    └── finance/
        ├── package.yml      # Package manifest
        └── lib/
            ├── invoice.rb        # Defines Invoice
            └── tax_calculator.rb # Defines TaxCalculator
```

### 2. Define Your Gemfile

**`Gemfile`:**
```ruby
source 'https://rubygems.org'

gem 'boxwerk'
gem 'money' # Example: gems are auto-required and globally accessible
```

### 3. Define Packages

**Root `package.yml`:**
```yaml
imports:
  - packages/finance # Will define a `Finance` module to hold finance package exports
```

**`packages/finance/package.yml`:**
```yaml
exports:
  - Invoice
  - TaxCalculator
```

### 4. Use in Your Application

**`app.rb`:**
```ruby
# No requires needed - imports are wired by Boxwerk
invoice = Finance::Invoice.new(10_000)
puts invoice.total  # => #<Money fractional:10000 currency:USD>
```

### 5. Run Your Application

```bash
RUBY_BOX=1 boxwerk run app.rb
```

Boxwerk handles setup, gem loading, package wiring, and script execution automatically.

## Example

See the [example/](example/) directory for a working multi-package application:

```bash
cd example
RUBY_BOX=1 boxwerk run app.rb
```

## CLI Usage

**Run a script:**
```bash
boxwerk run script.rb [args...]
```

**Interactive console** (currently runs in root box, not root package):
```bash
boxwerk console [irb-args...]
```

**Help:**
```bash
boxwerk help
```

## Package Configuration

A `package.yml` defines what a package exports and imports:

```yaml
exports:
  - PublicClass
  - PublicModule

imports:
  - packages/dependency1
  - packages/dependency2: Alias
```

### Exports

Constants that should be visible to packages that import this one.

### Imports

Package dependencies. **Not transitive**: if A imports B and B imports C, A cannot access C without explicitly importing it.

## Import Strategies

**Default namespace** (all exports under package name):
```yaml
imports:
  - packages/finance
# Result: Finance::Invoice, Finance::TaxCalculator
```

**Aliased namespace** (custom module name):
```yaml
imports:
  - packages/finance: Billing
# Result: Billing::Invoice, Billing::TaxCalculator
```
*Note: Single exports import directly without namespace*

**Selective import** (specific constants):
```yaml
imports:
  - packages/finance:
    - Invoice
    - TaxCalculator
# Result: Invoice, TaxCalculator (no namespace)
```

**Selective rename** (custom names):
```yaml
imports:
  - packages/finance:
      Invoice: Bill
      TaxCalculator: Calculator
# Result: Bill, Calculator
```

## Gem Handling

All gems in your `Gemfile` are:
- Automatically loaded in the root box via Bundler
- Accessible globally in all packages (no gem isolation)
- No manual `require` or `package.yml` declaration needed

## Known Issues

Related to Ruby::Box in Ruby 4.0+. See [Ruby::Box documentation](https://docs.ruby-lang.org/en/master/Ruby/Box.html) for details.

- **Gem requiring**: Crashes VM when requiring gems inside boxes after boot (workaround: gems pre-loaded in root box)
- **Console context**: Runs in root box instead of root package box due to IRB loading limitation
- **IRB autocomplete**: Disabled by since it currently crashes VMpe

## Architecture

**Boot process:**
1. Setup Bundler and require all gems in root box
2. Find root `package.yml` by searching up from current directory
3. Build and validate dependency graph (DAG)
4. Boot packages in topological order, creating isolated boxes
5. Wire imports by lazily loading exports and injecting constants
6. Execute command in root package context

**Components:**
- **CLI**: Parses commands, validates environment, delegates to Setup
- **Setup**: Finds root package, builds graph, creates registry, boots packages
- **Graph**: Builds DAG, validates no cycles, performs topological sort
- **Package**: Parses `package.yml`, tracks exports/imports/box
- **Loader**: Creates boxes, loads exports lazily (Zeitwerk conventions), wires imports
- **Registry**: Tracks booted packages, ensures single boot per package

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run the tests:

```bash
RUBY_BOX=1 bundle exec rake test
```

To install this gem onto your local machine, run `bundle exec rake install`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you shall be dual licensed as above, without any additional terms or conditions.
