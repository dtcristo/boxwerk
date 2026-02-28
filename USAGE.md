# Usage

Complete usage guide for Boxwerk — runtime package isolation for Ruby.

## Requirements

- Ruby 4.0+ with the `RUBY_BOX=1` environment variable set before process boot
- `package.yml` files ([Packwerk](https://github.com/Shopify/packwerk) format)

## Installation

Add `boxwerk` to your project's `gems.rb` or `Gemfile`:

```ruby
# gems.rb
source 'https://rubygems.org'

gem 'boxwerk'
```

Install and set up:

```bash
bundle install                       # Install gems (including boxwerk)
bundle binstubs boxwerk              # Create bin/boxwerk binstub
bin/boxwerk install                  # Install per-package gems
```

Run your application:

```bash
RUBY_BOX=1 bin/boxwerk run main.rb
```

## Package Configuration (package.yml)

Standard [Packwerk](https://github.com/Shopify/packwerk) format:

```yaml
# packs/finance/package.yml
enforce_dependencies: true
dependencies:
  - packs/util
  - packs/billing

enforce_privacy: true
public_path: public/              # default; directory of public constants
private_constants:
  - "::InternalHelper"            # explicitly blocked even if in public_path
```

| Field                  | Type     | Default   | Description                                     |
|------------------------|----------|-----------|-------------------------------------------------|
| `enforce_dependencies` | bool     | `false`   | Block access to undeclared dependencies          |
| `dependencies`         | list     | `[]`      | Direct dependency package paths                  |
| `enforce_privacy`      | bool     | `false`   | Restrict external access to public constants     |
| `public_path`          | string   | `public/` | Directory containing the package's public API    |
| `private_constants`    | list     | `[]`      | Constants blocked even if in the public path     |

## `pack_public: true` Sigil

Files outside the `public_path` can be individually marked public by adding a comment sigil in the first 5 lines:

```ruby
# pack_public: true
class SpecialService
  # accessible to dependents even though it lives in lib/, not public/
end
```

The sigil is matched with `#.*pack_public:\s*true`.

## CLI Reference

```
boxwerk <command> [options] [args...]
```

### Commands

#### `boxwerk run <script.rb> [args...]`

Run a Ruby script in a package box.

```bash
boxwerk run main.rb                       # Run in root package box
boxwerk run -p packs/finance main.rb      # Run in a specific package box
boxwerk run -g main.rb                    # Run in global context (no package)
```

#### `boxwerk exec <command> [args...]`

Execute a command (gem binstub) in the boxed environment. Resolves the command to its gem binstub path and evaluates it in the target box.

```bash
boxwerk exec rake test                   # Root package
boxwerk exec -p packs/util rake test     # Specific package
boxwerk exec --all rake test             # All packages sequentially
boxwerk exec -g rake test               # Global context (debugging)
```

With `--all`, each package runs in a separate subprocess for clean isolation (avoids `at_exit` conflicts from test frameworks like Minitest).

#### `boxwerk console [irb-args...]`

Start an IRB console with package constants accessible. IRB runs in `Ruby::Box.root` with a composite resolver that provides the target package's constants.

```bash
boxwerk console                          # Root package context
boxwerk console -p packs/finance         # Specific package context
```

IRB autocomplete is disabled (box-scoped constants are not visible to the completer).

#### `boxwerk info`

Show the dependency tree and package details: enforcements, dependencies, gems, and public paths. Also reports gem version conflicts between packages and the root `Gemfile`.

```bash
boxwerk info
```

Does not require `RUBY_BOX=1`.

#### `boxwerk install`

Run `bundle install` for every package that has a `Gemfile` or `gems.rb`. Processes packages in topological order.

```bash
bin/boxwerk install
```

Does not require `RUBY_BOX=1`.

#### `boxwerk help` / `boxwerk version`

Show usage or version.

### Options

| Flag                  | Short | Applies to              | Description                                        |
|-----------------------|-------|-------------------------|----------------------------------------------------|
| `--package <name>`    | `-p`  | `exec`, `run`, `console`| Run in a specific package box (default: `.`)       |
| `--all`               |       | `exec`                  | Run for all packages sequentially (subprocesses)   |
| `--global`            | `-g`  | `exec`, `run`, `console`| Run in the global context (no package)             |

## Per-Package Gems

Each package can have its own `Gemfile`/`gems.rb` and corresponding lockfile. Different packages can use different versions of the same gem.

```
packs/billing/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 5.0'
├── Gemfile.lock
└── lib/
    └── payment.rb        # require 'stripe' → gets v5
```

### Gem Isolation Model

- **Global gems** (root `Gemfile`) are loaded in the global context and inherited by all child boxes via `$LOADED_FEATURES` snapshot at box creation time
- **Per-package gems** are resolved from lockfiles and added to each box's `$LOAD_PATH` independently
- **Gems do NOT leak** across package boundaries — package A cannot see package B's gems, even if A depends on B
- **Cross-package version differences** are safe — each box has its own isolated `$LOAD_PATH`
- **Global override warning:** If a package defines a gem that's also in the root `Gemfile` at a different version, both versions load into memory (functionally correct but wastes memory). Boxwerk warns at boot time
- **Shared global gems:** Add a gem to the root `Gemfile` without `require: false` to share a single copy across all packages

Run `boxwerk install` to install gems for all packages.

## Constant Resolution

### Intra-Package: autoload

Each package's constants are registered as `autoload` entries in its box. When code references `Calculator`, Ruby's built-in autoload loads the file — standard Ruby behaviour.

### Cross-Package: const_missing

When a constant is not found in the current box, `Object.const_missing` fires. Boxwerk's per-box handler:

1. Iterates through declared direct dependencies
2. Checks each dependency for the constant (via file index or `const_get`)
3. Enforces privacy rules
4. Returns the constant value from the dependency's box
5. Raises `NameError` if no dependency has it

```ruby
# Simplified flow:
class Object
  def self.const_missing(const_name)
    deps.each do |dep|
      next unless dep.has_constant?(const_name)
      check_privacy!(const_name, dep)
      return dep.box.const_get(const_name)
    end
    raise NameError, "uninitialized constant #{const_name}"
  end
end
```

Constants are **not** wrapped in namespaces. `Invoice` is accessed as `Invoice`, not `Finance::Invoice`.

### Namespace Module Resolution

Parent modules are resolved by loading child files. If a file index has `Menu::Item` but no direct `Menu` entry, referencing `Menu` triggers autoload of a child file, which defines the `Menu` module as a side effect.

## Privacy Enforcement

Privacy is checked at `const_missing` time when resolving cross-package constants:

- **`public_path`** — Only files in this directory (default: `public/`) define the package's public API. Constants outside it are blocked.
- **`private_constants`** — Explicitly private constants, blocked even if in the public path.
- **`pack_public: true` sigil** — Files outside the public path can opt in to public visibility.

Violations raise `NameError` with a descriptive message:

```
Privacy violation: 'InternalHelper' is private to 'packs/finance'.
Only constants in the public path are accessible.
```

## Root Package vs Global Context

These are different concepts:

- **Root package** (`.`) — Your top-level `package.yml`. Gets its own `Ruby::Box` like any other package. Has dependencies and constants.
- **Global context** (`Ruby::Box.root`) — Where global gems are loaded via `Bundler.require`. Contains global gems and constants. All child boxes are copied from it.

The root package box is where your application code runs by default. The global context is an implementation detail — global gems live there and are inherited by all child boxes.

Use `--global` / `-g` for debugging gem loading issues. No package constants are accessible in this mode.

## Global Gems

Gems in the root `Gemfile`/`gems.rb` are loaded in `Ruby::Box.root` during boot:

1. `Bundler.setup` + `Bundler.require` run in the global context
2. All loaded gems become available in child boxes via `$LOADED_FEATURES` snapshot
3. Use `require: false` to keep a gem on `$LOAD_PATH` without loading it at boot

```ruby
# gems.rb
gem 'activesupport'                  # loaded globally, available everywhere
gem 'pry', require: false            # on $LOAD_PATH but not loaded
```

> **Note:** The root `gems.rb`/`Gemfile` is always for global gems shared across all packages. If your top-level package needs "package private" gems, use an implicit root (no `package.yml` at root) and create a `packs/main` package as your entry point with its own `gems.rb`.

## Testing

Run tests through Boxwerk to enforce package isolation:

```bash
boxwerk exec rake test                   # Root package tests
boxwerk exec -p packs/finance rake test  # Specific package tests
boxwerk exec --all rake test             # All packages sequentially
```

Each `--all` run spawns a separate subprocess per package for clean isolation — test frameworks like Minitest register tests globally via `at_exit`, which would conflict across packages in a single process.

## Configuration (`boxwerk.yml`)

An optional `boxwerk.yml` file at the project root configures Boxwerk behaviour.

```yaml
# boxwerk.yml
package_paths:
  - "packs/*"        # default: ["**/"]
```

| Field           | Type | Default   | Description                                       |
|-----------------|------|-----------|---------------------------------------------------|
| `package_paths` | list | `["**/"]` | Glob patterns for where to search for `package.yml` files |

By default, Boxwerk searches everywhere (`**/`) for `package.yml` files. Set `package_paths` to restrict the search to specific directories.

## Implicit Root Package

If no `package.yml` exists at the project root, Boxwerk creates an implicit root package with:

- `enforce_dependencies: false`
- `enforce_privacy: false`
- Automatic dependencies on all discovered packages

This is useful for gradually adopting Boxwerk — you can start with just sub-packages and no root `package.yml`. The implicit root can access constants from all packages without declaring explicit dependencies.

## Global Boot

### `global/` Directory

An optional `global/` directory at the project root provides global constants and initialization. Files in `global/` are required in the root box before package boxes are created, so all definitions are inherited by every package box.

Files follow Zeitwerk conventions:

```
global/
├── boot.rb           # Global boot script (optional)
├── config.rb         → Config
└── middleware.rb      → Middleware
```

```ruby
# global/config.rb
module Config
  SHOP_NAME = ENV.fetch('SHOP_NAME', 'My App')
  CURRENCY = '$'
end
```

### `global/boot.rb`

An optional `global/boot.rb` script runs in the root box after global files are loaded but before package boxes are created. Use it for initialization that all packages should inherit.

```ruby
# global/boot.rb
require 'dotenv/load'
puts "Booting #{Config::SHOP_NAME}..."
```

### Root-Level `boot.rb`

A `boot.rb` at the project root is a **root package** boot script — it runs in the root package's box (like any other package's `boot.rb`). This is different from `global/boot.rb` which runs in the root box.

### Use Cases

- **`global/boot.rb`** — Load environment variables, define global config, boot Rails
- **`boot.rb`** — Root package initialization (runs after all packages are booted)

## Per-Package Boot Scripts

Each package can have an optional `boot.rb` that runs after the package's own constants are scanned but before cross-package constants are wired. Use it to configure additional autoload dirs and Zeitwerk collapse:

```ruby
# packs/models/boot.rb
BOXWERK_CONFIG[:autoload_dirs] << "models"
BOXWERK_CONFIG[:collapse_dirs] << "lib/concerns"
```

## Circular Dependencies

Boxwerk allows circular dependencies. Both packages in a cycle are booted; the first visited in DFS order goes first. Dependencies in cycles are still wired normally.

## Relaxed Dependency Enforcement

When `enforce_dependencies: false`, `const_missing` searches ALL packages — not just declared dependencies. Explicit dependencies are searched first (in declared order), then remaining packages. Privacy rules still apply per-package.

## Examples

- [`examples/minimal/`](examples/minimal/) — Simplest setup: three packages, dependency enforcement, no gems
- [`examples/complex/`](examples/complex/) — Full-featured: namespaced constants, privacy enforcement, per-package gems, global gems, and tests
- [`examples/rails/`](examples/rails/) — Rails with ActiveRecord, foundation package, privacy
