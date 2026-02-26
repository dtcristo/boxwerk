<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk is the **runtime enforcement companion** to [Packwerk](https://github.com/Shopify/packwerk). While Packwerk provides static analysis of package dependencies at CI time, Boxwerk enforces those boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/master/Ruby/Box.html) constant isolation.

## How It Works

1. **Packwerk** defines packages via `package.yml` files with `dependencies` declarations
2. **Boxwerk** reads those same `package.yml` files at runtime
3. Each package gets its own **`Ruby::Box`** (isolated constant namespace)
4. Dependencies are exposed via **namespace proxy modules** with lazy `const_missing` resolution
5. Only **direct dependencies** are accessible — transitive dependencies are blocked

```
Packwerk (static, CI)     packwerk-extensions (config)     Boxwerk (runtime)
─────────────────────     ──────────────────────────       ──────────────────
• packwerk check          • enforce_privacy                • Ruby::Box per package
• packwerk validate       • enforce_visibility             • const_missing proxies
• package.yml format      • enforce_folder_privacy         • Zeitwerk inflection
• dependency graph        • enforce_layers                 • Privacy/Visibility/Layer
                          • layer in package.yml           • Per-package gem isolation
```

## Features

- **Box Isolation**: Each package runs in its own `Ruby::Box`, preventing constant leakage
- **Packwerk Compatible**: Uses standard Packwerk `package.yml` format — no custom config
- **Lazy Resolution**: Constants resolved on first access via `const_missing`, then cached
- **Transitive Prevention**: Only direct dependencies accessible; no transitive leakage
- **Namespace Proxies**: Dependencies accessed via derived namespace (e.g., `Finance::Invoice`)
- **Privacy Enforcement**: `enforce_privacy`, `public_path`, `private_constants`, `pack_public: true` sigil
- **Visibility Enforcement**: `enforce_visibility` with `visible_to` restricts which packages can see a package
- **Folder Privacy**: `enforce_folder_privacy` restricts access to sibling and parent packages only
- **Layer Enforcement**: `enforce_layers` with `layer` prevents lower layers from depending on higher ones
- **Per-Package Gem Isolation**: Each package can have its own `Gemfile` with isolated gem versions via `$LOAD_PATH` isolation
- **Zeitwerk Inflection**: Uses [Zeitwerk](https://github.com/fxn/zeitwerk) conventions for file→constant mapping

## Current Limitations

- No constant reloading support
- Package code must follow [Zeitwerk naming conventions](https://github.com/fxn/zeitwerk#file-structure)
- Console runs in root box, not root package box (due to IRB loading issues)
- `Ruby::Box` itself is experimental in Ruby 4.0

## Requirements

- Ruby 4.0.1+ with `RUBY_BOX=1` environment variable set
- [Packwerk](https://github.com/Shopify/packwerk) gem (added automatically as dependency)
- [Zeitwerk](https://github.com/fxn/zeitwerk) gem (added automatically as dependency)

## Quick Start

### 1. Create a Package Structure

```
my_app/
├── Gemfile
├── packwerk.yml             # Optional: layer definitions
├── package.yml              # Root package (Packwerk format)
├── app.rb                   # Your application entrypoint
└── packages/
    ├── finance/
    │   ├── package.yml      # Package manifest
    │   ├── Gemfile          # Optional: per-package gems
    │   └── lib/
    │       ├── invoice.rb
    │       └── tax_calculator.rb
    └── util/
        ├── package.yml
        └── lib/
            └── calculator.rb
```

### 2. Define Your Gemfile

**`Gemfile`:**
```ruby
source 'https://rubygems.org'

gem 'boxwerk'
```

### 3. Define Packages (Packwerk Format)

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

### 4. Use in Your Application

**`app.rb`:**
```ruby
# Constants accessed via namespace derived from package path
# packages/finance -> Finance::
invoice = Finance::Invoice.new(10_000)
puts invoice.total
```

### 5. Run Your Application

```bash
RUBY_BOX=1 boxwerk run app.rb
```

Boxwerk handles Bundler setup, gem loading, package wiring, and script execution automatically.

## Constant Resolution

When a package declares `dependencies: [packages/finance]`, Boxwerk:

1. Creates a `Finance` namespace proxy module (derived from `packages/finance` using Zeitwerk inflection)
2. Injects it into the package's box via `const_set`
3. When `Finance::Invoice` is accessed, `const_missing` fires on the proxy
4. Resolves `Invoice` from the finance package's box via `const_get`
5. Caches the result via `const_set` for fast subsequent access

### Transitive Dependency Prevention

```
Root depends on: [packages/finance]
Finance depends on: [packages/util]
```

- Root can access `Finance::Invoice` ✓ (direct dependency)
- Root **cannot** access `Util::Calculator` ✗ (transitive, not declared)
- Finance can access `Util::Calculator` ✓ (direct dependency)

## Example

See the [example/](example/) directory for a working multi-package application demonstrating privacy, visibility, layers, and gem isolation:

```bash
cd example
bundle install
RUBY_BOX=1 boxwerk run app.rb
```

## CLI Usage

**Run a script:**
```bash
boxwerk run script.rb [args...]
```

**Interactive console:**
```bash
boxwerk console [irb-args...]
```

**Help:**
```bash
boxwerk help
```

## Package Configuration

Boxwerk uses Packwerk's standard `package.yml` format with all [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) config keys — no custom extensions:

```yaml
# packages/finance/package.yml
enforce_dependencies: true
dependencies:
  - packages/util

# Privacy (packwerk-extensions)
enforce_privacy: true
public_path: app/public/
private_constants:
  - "::Finance::InternalHelper"

# Visibility (packwerk-extensions)
enforce_visibility: true
visible_to:
  - packages/billing
  - .

# Folder privacy (packwerk-extensions)
enforce_folder_privacy: true

# Layers (packwerk-extensions)
enforce_layers: true
layer: core
```

### Dependencies

Packages listed under `dependencies` are accessible at runtime via namespace modules.
The namespace is derived from the package path using Zeitwerk conventions: `packages/finance` → `Finance::`, `packages/tax_calc` → `TaxCalc::`.

Dependencies are **not transitive**: if A depends on B and B depends on C,
A cannot access C without explicitly declaring it as a dependency.

### Integration with Packwerk

Use Packwerk for static analysis during development/CI:

```bash
bin/packwerk check    # Static analysis of dependency violations
bin/packwerk validate # Validate package system structure
```

Use Boxwerk for runtime enforcement:

```bash
RUBY_BOX=1 boxwerk run app.rb  # Runtime constant isolation
```

## Privacy Enforcement

When `enforce_privacy: true`, only a package's **public API** is accessible to dependents — private constants are blocked at runtime.

```yaml
# packages/finance/package.yml
enforce_privacy: true
public_path: app/public/     # Optional, default: app/public/
private_constants:            # Optional, explicitly private constants
  - "::Finance::InternalHelper"
```

### Public Path

Only constants defined in `public_path` are accessible from outside the package:

```
packages/finance/
├── package.yml
├── app/
│   └── public/           # Public API (accessible to dependents)
│       └── invoice.rb    # Finance::Invoice ✓
├── lib/
│   └── internal.rb       # Finance::Internal ✗ (private)
```

### `pack_public: true` Sigil

Individual files outside the public path can be made public:

```ruby
# pack_public: true
class SpecialService
  # Public despite being in lib/, not app/public/
end
```

### Private Constants

Explicitly block specific constants, even if they would otherwise be public:

```yaml
private_constants:
  - "::Finance::Invoice"   # Blocked even if in public_path
```

## Visibility Enforcement

When `enforce_visibility: true`, only packages listed in `visible_to` can depend on this package. Other packages will not have the namespace proxy wired — access raises `NameError`.

```yaml
# packages/internal_billing/package.yml
enforce_visibility: true
visible_to:
  - packages/billing       # Only billing can see this package
  - .                      # Root package can also see it
```

## Folder Privacy Enforcement

When `enforce_folder_privacy: true`, only sibling packages (same parent directory) and parent/ancestor packages can access this package:

```
packs/
├── platform/
│   ├── packs/
│   │   ├── auth/          # enforce_folder_privacy: true
│   │   └── users/         # ✓ Can access auth (sibling)
│   └── package.yml        # ✓ Can access auth (parent)
└── features/
    └── billing/           # ✗ Cannot access auth (unrelated)
```

## Layer Enforcement

Define architectural layers in `packwerk.yml` (ordered highest to lowest) and assign packages to layers. Higher layers can depend on lower layers, but not vice versa.

**`packwerk.yml`:**
```yaml
layers:
  - feature        # Highest layer
  - core
  - utility        # Lowest layer
```

**`packages/billing/package.yml`:**
```yaml
enforce_layers: true
layer: feature
dependencies:
  - packages/util  # ✓ feature → utility (allowed)
```

**`packages/util/package.yml`:**
```yaml
enforce_layers: true
layer: utility
# Cannot depend on feature or core packages
```

Layer violations raise `Boxwerk::LayerViolationError` at boot time.

## Per-Package Gem Isolation

Each package can optionally have its own `Gemfile` (or `gems.rb`) with isolated gem dependencies. Different packages can use different versions of the same gem — `Ruby::Box` isolates `$LOAD_PATH` and `$LOADED_FEATURES` per box.

```
packages/billing/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 5.0'
├── Gemfile.lock          # Locked to stripe 5.x
└── lib/
    └── payment.rb        # require 'stripe' → gets v5

packages/checkout/
├── package.yml
├── Gemfile               # gem 'stripe', '~> 10.0'
├── Gemfile.lock          # Locked to stripe 10.x
└── lib/
    └── payment.rb        # require 'stripe' → gets v10
```

### Setup

1. Create a `Gemfile` (or `gems.rb`) in the package directory
2. Run `cd packages/billing && bundle install` to install and generate `Gemfile.lock`
3. Boxwerk reads `Gemfile.lock` at boot, resolves gem paths via `Gem::Specification`, and configures the box's `$LOAD_PATH`
4. Package code can `require` gems normally — they load from the box's isolated load path

### How It Works

- Lockfile parsed with `Bundler::LockfileParser` (no subprocess at runtime)
- Gem paths resolved via `Gem::Specification.find_by_name` with recursive dependency traversal
- Each gem's `full_require_paths` added to the box's `$LOAD_PATH`
- Gems are fully isolated: different `object_id`s, no cross-box contamination

## Gem Handling (Global)

Gems in the root `Gemfile` are:
- Automatically loaded in the root box via Bundler
- Accessible globally in all packages
- No manual `require` or `package.yml` declaration needed

## Zeitwerk Inflection

Boxwerk uses [Zeitwerk](https://github.com/fxn/zeitwerk) conventions for deriving constant names from file and directory paths:

- `packages/finance` → `Finance`
- `packages/tax_calc` → `TaxCalc`
- `packages/html_parser` → `HtmlParser`

This follows the same naming convention used by Zeitwerk autoloading in Rails and standalone Ruby applications.

## Complementary Tools

### Packwerk

[Packwerk](https://github.com/Shopify/packwerk) provides static analysis at CI time. Use it alongside Boxwerk for comprehensive enforcement:

```bash
bin/packwerk check      # Static: catches violations in CI
RUBY_BOX=1 boxwerk run  # Runtime: enforces at execution
```

### Packs

[Packs](https://github.com/rubyatscale/packs) is a CLI tool for managing package structure (creating, moving, listing packs). It's complementary to Boxwerk — use it for developer workflow, not enforcement.

```bash
bin/packs create packages/billing   # Create new package structure
bin/packs list                      # List all packages
```

## Known Issues

Related to Ruby::Box in Ruby 4.0+. See [Ruby::Box documentation](https://docs.ruby-lang.org/en/master/Ruby/Box.html) for details.

- **Console context**: Runs in root box instead of root package box due to IRB crash
- **IRB autocomplete**: Disabled since it currently crashes VM

## Architecture

**Boot process:**
1. Setup Bundler and require all gems in root box
2. Find root `package.yml` by searching up from current directory
3. Discover all packages via Packwerk's `PackageSet`
4. Read layer definitions from `packwerk.yml` (if present)
5. Validate dependency graph (DAG — no cycles)
6. Boot packages in topological order, creating isolated boxes
7. For each package: resolve per-package gems → load code → wire namespaces
8. Enforce visibility, folder privacy, layer, and privacy constraints during wiring
9. Execute command in root package context

**Components:**
- **CLI**: Parses commands, validates environment, delegates to Setup
- **Setup**: Finds root, orchestrates PackageResolver + BoxManager
- **PackageResolver**: Uses Packwerk to discover packages, builds dependency map, topological sort
- **BoxManager**: Creates `Ruby::Box` per package, loads code, wires namespace proxies, orchestrates all checkers
- **ConstantResolver**: Creates proxy modules with `const_missing` for lazy resolution
- **PrivacyChecker**: Reads `enforce_privacy`, `public_path`, `private_constants` config
- **VisibilityChecker**: Reads `enforce_visibility`, `visible_to` config
- **FolderPrivacyChecker**: Reads `enforce_folder_privacy` config, checks sibling/parent relationships
- **LayerChecker**: Reads `enforce_layers`, `layer` config and `layers` from `packwerk.yml`
- **GemResolver**: Parses per-package `Gemfile.lock`, resolves gem paths via `Gem::Specification`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run the tests:

```bash
RUBY_BOX=1 bundle exec rake test
```

To install this gem onto your local machine, run `bundle exec rake install`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you shall be licensed as above, without any additional terms or conditions.
