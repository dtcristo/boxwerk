# Boxwerk

Boxwerk is a runtime package system for Ruby with strict isolation of constants using Ruby 4.0's [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html). It is used to organize code into packages with explicit dependency graphs and strict access to constants between packages. It is inspired by [Packwerk](https://github.com/Shopify/packwerk), a static package system.

## Features

- **Strict Isolation**: Each package runs in its own `Ruby::Box`, preventing constants from leaking without explicit imports or exports.
- **Explicit Dependencies**: Dependencies are declared in `package.yml` files, forming a validated DAG.
- **Ergonomic Imports**: Flexible import strategies (namespaced, aliased, selective, renamed).

## Limtations

- There is no isolation of gems.
- Gems are required to be eager loaded in the root box to be accessible in packages.
- No support for reloading of constants.
- Exported constants must follow Zeitwerk naming conventions for their source location.

## Requirements

- Ruby 4.0+ with [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html) support
- `RUBY_BOX=1` environment variable must be set at process startup

## Quick Start

### 1. Create a Package Structure

```
my_app/
├── Gemfile                  # Your gem dependencies
├── package.yml              # Root package
├── app.rb                   # Your application entrypoint
└── packages/
    └── billing/
        ├── package.yml      # Package manifest
        └── lib/
            └── invoice.rb   # Package code
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

**`packages/finance/lib/invoice.rb`:**
```ruby
class Invoice
  def initialize(amount_cents)
    # Money gem is accessible because it's in the Gemfile
    @amount = Money.new(amount_cents, 'USD')
  end

  def total
    @amount
  end
end
```

**`packages/finance/lib/tax_calculator.rb`:**
```ruby
class TaxCalculator
  # ...
end
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

Boxwerk automatically:
1. Sets up Bundler
2. Requires all gems from your Gemfile in the root box
3. Loads and wires all packages
4. Executes your script in the root package context

## Usage

### Running Scripts

Execute a Ruby script in the root package context:

```bash
boxwerk run script.rb [args...]
```

The script has access to:
- All gems from your Gemfile (automatically required)
- All imports defined in the root `package.yml`

### Interactive Console

TODO: This feature is currenly broken and will run IRB from the root box, not the root package as desired.

Start an IRB session in the root package context:

```bash
boxwerk console [irb-args...]
```

All imports and gems are available for interactive exploration.

### Help

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

Dependencies this package needs. **Note**: Dependencies are NOT transitive. If package A imports B, and B imports C, then A cannot access C unless it explicitly imports it.

## Import Strategies

Boxwerk supports four import strategies in `package.yml`:

### 1. Default Namespace

Import all exports under a module named after the package:

```yaml
imports:
  - packages/finance
```

Result: `Finance::Invoice`, `Finance::TaxCalculator`

### 2. Aliased Namespace

Import under a custom module name:

```yaml
imports:
  - packages/finance: Billing
```

Result: `Billing::Invoice`, `Billing::TaxCalculator`

**Single Export Optimization**: If a package exports only one constant, it's imported directly (not wrapped in a module):

```yaml
# util exports only Calculator
imports:
  - packages/util: Calc
```

Result: `Calc` (not `Calc::Calculator`)

### 3. Selective Import

Import specific constants directly:

```yaml
imports:
  - packages/finance:
    - Invoice
    - TaxCalculator
```

Result: `Invoice`, `TaxCalculator` (no namespace)

### 4. Selective Rename

Import specific constants with custom names:

```yaml
imports:
  - packages/finance:
      Invoice: Bill
      TaxCalculator: Calculator
```

Result: `Bill`, `Calculator`

## Gems and Packages

### How Gems Work in Boxwerk

When you run `boxwerk`, all gems in your `Gemfile` are:
1. Automatically loaded via Bundler in the root box
2. Accessible globally in all package boxes (gems are not isolated)

This means:
- You can use any gem from your Gemfile in any package.
- Gems don't need to be declared in `package.yml`.
- You do not `require` gems manually.

### Isolation Model

- **Root Box**: The box where Ruby bootstraps and all builtin classes/modules are defined. In Boxwerk, the root box performs all setup operations (Bundler setup, gem loading, dependency graph building, package box creation, and import wiring).
- **Main Box**: The first user box created automatically by Ruby (copied from root box). In Boxwerk, it only runs the `exe/boxwerk` executable file, which then calls into the root box to execute the setup. The main box has no other purpose.
- **Package Boxes**: Each package (including root package) runs in its own isolated `Ruby::Box` (created by copying from root box after gems are loaded).
- **Box Inheritance**: All boxes are created via copy-on-write from the root box, inheriting builtin classes and loaded gems.
- **Gems are Global**: All gems from Gemfile are accessible in all boxes (loaded in root box before package boxes are created).
- **Package Exports are Isolated**: Only explicit imports from packages are accessible.
- **No Transitive Access**: Packages can only see their explicit imports.

For more details on how Ruby::Box works, see the [official Ruby::Box documentation](https://docs.ruby-lang.org/en/master/Ruby/Box.html).

## Known Issues

These issues are related to the current state of Ruby::Box in Ruby 4.0+. See the [Ruby::Box documentation](https://docs.ruby-lang.org/en/master/Ruby/Box.html) for known issues with the feature itself.

### Gem Requiring in Boxes

Requiring any gem from within a box (after boot) currently crashes the Ruby VM. This is likely an issue with Ruby::Box itself. As a workaround, Boxwerk automatically requires all gems from the Gemfile in the root box before creating package boxes, so gems are already loaded and accessible everywhere.

### Console Context

The console does not correctly run in the root package box—it runs in the context of the root box instead. It should run in the root package box. However, if we attempt to `require 'irb'` in the root package box, the Ruby VM crashes due to the gem requiring issue described above.

### IRB Autocomplete

Autocomplete is disabled for the console/IRB by default. When enabled, the Ruby VM crashes as soon as any key is pressed. This appears to be an issue with Ruby::Box and IRB's autocomplete feature interacting poorly.

## Architecture

### Boot Process

1. Setup Bundler and require all gems in the root box
2. Find root `package.yml` (searches up from current directory)
3. Build dependency graph from package manifests
4. Validate dependency graph (no circular dependencies)
5. Boot packages in topological order
6. Wire imports into each package box
7. Execute command in root package context

### Internal Components

Boxwerk consists of several internal components that work together to provide package isolation:

#### `Boxwerk::CLI`

The command-line interface handler that:
- Parses commands (`run`, `console`, `help`)
- Validates the Ruby environment (checks for `RUBY_BOX=1` and Ruby::Box support)
- Delegates to `Boxwerk::Setup` for the boot process
- Executes the requested command in the root package's box context

#### `Boxwerk::Setup`

The setup orchestrator that:
- Searches up the directory tree to find the root `package.yml`
- Creates a `Boxwerk::Graph` instance to build and validate the dependency graph
- Creates a `Boxwerk::Registry` instance to track booted packages
- Calls `Boxwerk::Loader.boot_all` to boot all packages in topological order
- Returns the loaded graph for introspection

#### `Boxwerk::Graph`

The dependency graph builder that:
- Parses the root `package.yml` and recursively discovers all package dependencies
- Builds a directed acyclic graph (DAG) of package relationships
- Validates that there are no circular dependencies
- Performs topological sorting to determine boot order (dependencies before consumers)
- Provides access to all packages in the graph

#### `Boxwerk::Package`

The package manifest parser that:
- Represents a single package with its configuration
- Parses `package.yml` files to extract exports and imports
- Normalizes the polymorphic import syntax (String, Array, Hash)
- Stores the package path, name, exports, imports, and box reference
- Tracks which exports have been loaded via `loaded_exports` hash (export name → file path)
- Tracks whether the package has been booted

#### `Boxwerk::Loader`

The package loader that:
- Creates a new `Ruby::Box` for each package (including the root package)
- Loads exported constants lazily on-demand when they are imported by other packages
- Uses Zeitwerk naming conventions to discover file locations for exported constants
- Caches loaded exports in `package.loaded_exports` to avoid redundant file loading
- Wires imports by injecting constants from dependency boxes into consumer boxes
- Implements all four import strategies (default namespace, aliased namespace, selective import, selective rename)
- Handles the single-export optimization for namespace imports
- Registers each booted package in the registry
- Only loads files that define exported constants, never loading non-exported code

#### `Boxwerk::Registry`

The package registry that:
- Tracks all booted package instances
- Allows packages to be retrieved by name during the wiring phase
- Ensures each package is only booted once
- Provides a clean interface for package lookup

## Example

See the [example/](example/) directory for a complete working example with:

- Multi-package application
- Gem usage
- Transitive dependency demonstration
- Isolation verification
- Console usage examples

Run it with:

```bash
cd example
RUBY_BOX=1 boxwerk run app.rb
```

Or explore interactively:

```bash
cd example
RUBY_BOX=1 boxwerk console
```

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
