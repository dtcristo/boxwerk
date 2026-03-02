# Usage

Complete usage guide for Boxwerk — runtime package isolation for Ruby.

## Requirements

- Ruby 4.0+ with the `RUBY_BOX=1` environment variable set before process boot
- `package.yml` files ([Packwerk](https://github.com/Shopify/packwerk) format)

## Installation

### With Bundler

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
bin/boxwerk install                  # Install per-package gems (works without pre-installed project gems)
```

Run your application:

```bash
RUBY_BOX=1 bin/boxwerk run main.rb
```

### Without Bundler

Boxwerk works without any Gemfile. Install it as a system gem:

```bash
gem install boxwerk
```

Run directly:

```bash
RUBY_BOX=1 boxwerk run main.rb
```

In this mode, no gems are loaded into the global context (except Boxwerk itself). Per-package gems are still supported if Bundler is available on the system.

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
| `enforce_dependencies` | bool     | `false`   | Block access to undeclared dependencies         |
| `dependencies`         | list     | `[]`      | Direct dependency package paths                 |
| `enforce_privacy`      | bool     | `false`   | Restrict external access to public constants    |
| `public_path`          | string   | `public/` | Directory containing the package's public API   |
| `private_constants`    | list     | `[]`      | Constants blocked even if in the public path    |

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
boxwerk run main.rb                             # Run in root package box
boxwerk run --package packs/finance main.rb     # Run in a specific package box
boxwerk run --global main.rb                    # Run in global context (no package)
```

#### `boxwerk exec <command> [args...]`

Execute a command in the boxed environment. Boxwerk looks for the command in this order:

1. **Project binstub** — `./bin/<command>` in the project root
2. **Gem binstub** — resolved via `Gem.bin_path`
3. **Shell command** — falls back to running the command as a shell process in the package directory

Project binstubs take precedence, allowing custom command entry points (e.g. a `bin/rails` that sets `APP_PATH` and requires `rails/commands`).

```bash
boxwerk exec rake test                          # Root package
boxwerk exec --package packs/util rake test     # Specific package
boxwerk exec --all rake test                    # All packages sequentially
```

With `--all`, each package runs in a separate subprocess for clean isolation (avoids `at_exit` conflicts from test frameworks like Minitest).

#### `boxwerk console [irb-args...]`

Start an IRB console with package constants accessible. IRB runs in `Ruby::Box.root` with a composite resolver that provides the target package's constants.

```bash
boxwerk console                          # Root package context
boxwerk console --package packs/finance  # Specific package context
boxwerk console --global                 # Global context
```

IRB autocomplete is disabled (box-scoped constants are not visible to the completer).

#### `boxwerk info`

Boot the application and show runtime autoload structure: config, dependency tree, global section, per-package enforcements/dependencies/autoload dirs/gems/constants. Also reports gem version conflicts.

```bash
RUBY_BOX=1 boxwerk info
```

Output sections:
- **Config** — `boxwerk.yml` settings with defaults filled in
- **Dependency Graph** — tree view; circular dependencies are marked `(circular)`
- **Global** — boot script, autoload or `eager_load` dirs (label is `eager_load` when eager loading enabled), gems
- **Packages** — each package with enforcements, dependencies, `autoload`/`eager_load` dirs, `collapse` dirs, `ignore` dirs, `pack_public` constants, explicit private constants, and direct gems

Requires `RUBY_BOX=1` (boots the application to gather runtime autoload information).

When eager loading is enabled (`eager_load_global` / `eager_load_packages`), the autoload section label becomes `eager_load`.

#### `boxwerk install`

Run `bundle install` for every package that has a `Gemfile` or `gems.rb`. Installs global (root) gems first, then packages.

```bash
bin/boxwerk install
```

Does not require `RUBY_BOX=1`. Works without pre-installing global project gems first — the binstub skips `bundler/setup` for this command so you can run it as the first step after cloning a project.

#### `boxwerk help` / `boxwerk version`

Show usage or version.

### Options

| Flag                      | Short | Applies to              | Description                                        |
|---------------------------|-------|-------------------------|----------------------------------------------------|
| `--package <name>`        | `-p`  | `exec`, `run`, `console`| Run in a specific package box (default: `.`)       |
| `--all`                   | `-a`  | `exec`                  | Run for all packages sequentially (subprocesses)   |
| `--global`                | `-g`  | `exec`, `run`, `console`| Run in the global context (no package)             |
| `--package-paths <paths>` |       | `exec`, `run`, `console`| Comma-separated package path globs (override `boxwerk.yml`) |
| `--eager-load-global`     |       | `exec`, `run`, `console`| Enable global eager loading                        |
| `--no-eager-load-global`  |       | `exec`, `run`, `console`| Disable global eager loading                       |
| `--eager-load-packages`   |       | `exec`, `run`, `console`| Enable package eager loading                       |
| `--no-eager-load-packages`|       | `exec`, `run`, `console`| Disable package eager loading                      |

CLI config options override `boxwerk.yml` values. This enables quick configuration without creating a config file.

Package names passed to `--package` are normalized: leading `./` and trailing `/` are stripped, so `./packs/loyalty`, `packs/loyalty/`, and `packs/loyalty` all refer to the same package.

## Per-Package Gems

Each package can have its own `Gemfile`/`gems.rb` and corresponding lockfile. Different packages can use different versions of the same gem.

```
packs/billing/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 5.0'
├── Gemfile.lock
└── lib/
    └── payment.rb        # Stripe auto-required, ready to use
```

### Gem Isolation Model

- **Global gems** (root `Gemfile`) are loaded in the global context and inherited by all child boxes via `$LOADED_FEATURES` snapshot at box creation time
- **Per-package gems** are resolved from lockfiles and added to each box's `$LOAD_PATH` independently
- **Auto-required:** Gems declared in a package's `Gemfile`/`gems.rb` are automatically required in the package box (like Bundler's default behaviour). No manual `require` needed
- **`require: false`** — Gems declared with `require: false` are added to `$LOAD_PATH` but not auto-required
- **Custom require:** `gem 'foo', require: 'foo/bar'` auto-requires `foo/bar` instead of `foo`
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

- **Root package** (`.`) — Your top-level `package.yml`. Gets its own `Ruby::Box` like any other package. Has dependencies and constants. This is where your application code runs by default.
- **Global context** (`Ruby::Box.root`) — Where global gems are loaded via `Bundler.require`. Contains global gems and constants. All child boxes are copied from it.

The global context is an implementation detail of how `Ruby::Box` works. Constants and files loaded in the global context before package boxes are created are inherited by **all** package boxes. This is because each `Ruby::Box.new` creates a snapshot of `Ruby::Box.root` at that moment.

This has important implications:

- Global gems loaded via `Bundler.require` are available everywhere (loaded before boxes)
- Constants defined in `global/` files are available everywhere (required before boxes)
- Code in `global/boot.rb` runs before any package boxes exist
- Anything loaded **after** box creation is only visible in the box that loaded it

Use `--global` / `-g` to run commands in the global context directly. A composite resolver is installed on `Ruby::Box.root` so that **all** package constants are accessible — useful for scripts, debugging, or tools that need cross-package access without picking a single package.

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

### Gems with Internal Autoloading

Some gems (like Rails) use Zeitwerk internally to autoload their own constants. When loaded via `Bundler.require` in the global context, these autoloads are registered as pending entries in `Ruby::Box.root`. Because child boxes inherit a snapshot of the root box at creation time, pending autoloads may not resolve correctly in child boxes.

Boxwerk runs `Zeitwerk::Loader.eager_load_all` after global boot to resolve all pending autoloads. If your gem needs additional setup before eager loading (e.g. requiring sub-components), do this in `global/boot.rb`:

```ruby
# global/boot.rb
require "active_record/railtie"      # register Zeitwerk autoloads
require "action_controller/railtie"
# Boxwerk runs Zeitwerk::Loader.eager_load_all after this script
```

## Testing

Run tests through Boxwerk to enforce package isolation:

```bash
boxwerk exec rake test                          # Root package tests
boxwerk exec --package packs/finance rake test  # Specific package tests
boxwerk exec --all rake test                    # All packages sequentially
```

Each `--all` run spawns a separate subprocess per package for clean isolation — test frameworks like Minitest register tests globally via `at_exit`, which would conflict across packages in a single process.

## Configuration (`boxwerk.yml`)

An optional `boxwerk.yml` file at the project root configures Boxwerk behaviour.

```yaml
# boxwerk.yml
package_paths:
  - "packs/*"        # default: ["**/"]
eager_load_global: true   # default: true
eager_load_packages: false # default: false
```

| Field                 | Type | Default   | Description                                                |
|-----------------------|------|-----------|------------------------------------------------------------|
| `package_paths`       | list | `["**/"]` | Glob patterns for where to search for `package.yml` files  |
| `eager_load_global`   | bool | `true`    | Eager-load `global/` files and Zeitwerk constants at boot  |
| `eager_load_packages` | bool | `false`   | Eager-load all constants in each package box after boot    |

By default, Boxwerk searches everywhere (`**/`) for `package.yml` files. Set `package_paths` to restrict the search to specific directories.

### Eager Loading

- **`eager_load_global`** — When `true` (default), requires all files in `global/` and any dirs registered via `Boxwerk.global.autoloader.push_dir`, then runs `Zeitwerk::Loader.eager_load_all`. This ensures constants are defined before child boxes are created. When `false`, global constants are registered as lazy autoloads (accessible on demand, e.g. in `global/boot.rb`) but not eagerly required.
- **`eager_load_packages`** — When `true`, eager-loads all constants in each package box immediately after it boots. When `false` (default), constants are lazy-loaded via autoload on first access.

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
├── config.rb         # Config
└── middleware.rb     # Middleware
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

#### `Boxwerk.global.autoloader`

Use `Boxwerk.global.autoloader` in `global/boot.rb` (or anywhere in global context) to register additional root-level autoload directories. Constants loaded this way are available in all package boxes.

```ruby
# global/boot.rb
# Load shared utilities from a custom lib/ dir
Boxwerk.global.autoloader.push_dir(File.expand_path('../lib', __dir__))
```

Methods:

```ruby
Boxwerk.global.autoloader.push_dir("lib")       # Register lazy autoloads
Boxwerk.global.autoloader.collapse("lib/utils")  # Collapse namespace
Boxwerk.global.autoloader.setup                  # Register any pending dirs
Boxwerk.global.autoloader.eager_load!            # Eagerly require all registered dirs
```

`push_dir` and `collapse` auto-call `setup` (lazy autoload registration), so constants are accessible immediately in `boot.rb` via the autoload mechanism. Files are NOT eagerly required by `push_dir`. When `eager_load_global: true`, Boxwerk calls `eager_load!` after `global/boot.rb` so child boxes inherit the constants eagerly.

### Root-Level `boot.rb`

A `boot.rb` at the project root is a **root package** boot script — it runs in the root package's box (like any other package's `boot.rb`). This is different from `global/boot.rb` which runs in the root box.

### Use Cases

- **`global/boot.rb`** — Load environment variables, define global config, manually eager load constants (e.g. Rails internals)
- **`boot.rb`** — Root package initialization, e.g. booting Rails (see [Rails example](examples/rails/)). Runs after all packages are booted

## Per-Package Boot Scripts

Each package can have an optional `boot.rb` that runs after the package's own constants are scanned and per-package gems are loaded, but before cross-package constants are wired. It can be used to configure additional autoload dirs and collapse:

```ruby
# packs/models/boot.rb
pkg = Boxwerk.package

pkg.name           # => "packs/models"
pkg.root?          # => false
pkg.config         # => frozen hash of package.yml values
pkg.root_path      # => absolute path to the package directory
pkg.autoloader     # => autoload configuration object

pkg.autoloader.push_dir("models")
pkg.autoloader.collapse("lib/concerns")  # Promotes lib/concerns/* to parent namespace
pkg.autoloader.ignore("lib/legacy")      # Excludes lib/legacy/* from autoloading
```

`collapse` removes the intermediate namespace directory from the constant hierarchy. For example, collapsing `lib/analytics/formatters` means files in that directory are accessible as `Analytics::CsvFormatter` rather than `Analytics::Formatters::CsvFormatter`. The `Formatters` intermediate constant is removed from the box.

`ignore` prevents files in the directory from being autoloaded. Accessing any constant from that directory raises `NameError`.

### `autoloader.setup`

`push_dir` and `collapse` automatically call `setup`, registering constants immediately so they are available during `boot.rb` execution. You can also call `autoloader.setup` explicitly to ensure dirs are registered at a specific point:

```ruby
# packs/svc/boot.rb
pkg = Boxwerk.package
pkg.autoloader.push_dir("extras")

# Helper is available immediately (push_dir auto-called setup)
Helper.configure(ENV["API_KEY"])
```

`setup` can be called multiple times — each call registers only the dirs added since the last call.

`Boxwerk.package` returns a `PackageContext` accessible from anywhere inside a package box. The `BOXWERK_PACKAGE` constant is also set in each package box for direct access.

### Monkey Patch Isolation

Because each package runs in its own `Ruby::Box`, monkey patches defined in a
package are isolated to that box:

```ruby
# packs/kitchen/boot.rb
class String
  def to_order_ticket
    "🎫 #{upcase}"
  end
end
```

Code inside the kitchen package can call `"Latte".to_order_ticket`, but other
packages and the root context will not see the method.

## Circular Dependencies

Boxwerk allows circular dependencies. Both packages in a cycle are booted; the first visited in DFS order goes first. Dependencies in cycles are still wired normally.

## Relaxed Dependency Enforcement

When `enforce_dependencies: false`, `const_missing` searches ALL packages — not just declared dependencies. Explicit dependencies are searched first (in declared order), then remaining packages. Privacy rules still apply per-package.

## Examples

- [`examples/minimal/`](examples/minimal/) — Simplest setup: three packages, dependency enforcement, no gems
- [`examples/complex/`](examples/complex/) — Full-featured: namespaced constants, privacy enforcement, per-package gems, global gems, and tests
- [`examples/rails/`](examples/rails/) — Rails with ActiveRecord, foundation package, privacy
