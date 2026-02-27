# Architecture

This document describes how Boxwerk works internally.

## Overview

Boxwerk enforces package boundaries at runtime using Ruby::Box isolation. Each package gets its own `Ruby::Box` instance. Constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

```
┌─────────────────────────────────────────────────────┐
│                    Root Box                          │
│  (Bundler + global gems loaded here)                │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ root pkg │  │ finance  │  │   util   │  ...      │
│  │  (box)   │  │  (box)   │  │  (box)   │          │
│  └──────────┘  └──────────┘  └──────────┘          │
│       │              │              │                │
│       │  const_missing             autoload          │
│       │  searches deps             resolves files    │
└─────────────────────────────────────────────────────┘
```

## Ruby::Box Primer

[`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) provides in-process isolation of classes, modules, and constants. Boxwerk relies on these specific behaviours:

### Box Types

- **Root box** — A single box per Ruby process. Created during bootstrap. All builtin classes/modules live here. The source for copy-on-write when creating user boxes.
- **Main box** — A user box automatically created at bootstrap, copied from the root box. The user's main program runs here.
- **User boxes** — Created with `Ruby::Box.new`, copied from the root box. All user boxes are flat (no nesting). This is what Boxwerk creates for each package.

### Key Behaviours

- **File scope.** One `.rb` file runs in a single box. Methods and procs defined in that file always execute in that file's box, even when called from another box.
- **Top-level constants.** Constants defined at the top level are constants of `Object` within that box. From outside, `box::Foo` accesses them.
- **Monkey patch isolation.** Reopened built-in classes are visible only within the box that defined them.
- **Global variable isolation.** `$LOAD_PATH`, `$LOADED_FEATURES`, and other globals are isolated per box. `$LOAD_PATH` and `$LOADED_FEATURES` use the *loading box* (not current box) for `require` resolution.
- **Copy-on-write.** `Ruby::Box.new` copies the root box's class extensions. Anything loaded into the root box *before* creating a user box is inherited. Anything loaded *after* is not.
- **`box.eval(code)`** — Evaluates Ruby code in the box's context, like loading a file.
- **`box.require(path)`** — Requires a file in the box's context. Subsequent requires from that file also run in the same box.

### Important Implications

1. **Order matters.** Gems loaded into the root box via `Bundler.require` before `Ruby::Box.new` are inherited by all user boxes. This is how Boxwerk provides "global gems".
2. **No cross-box method inheritance.** A `const_missing` hook defined on `Module` in one box does not fire in another box. Boxwerk must install resolvers per-box.
3. **`$LOAD_PATH` per box.** Each box has its own `$LOAD_PATH`, which enables per-package gem version isolation.

## Boot Sequence

The `boxwerk` executable (`exe/boxwerk`) orchestrates the boot:

```
1. exe/boxwerk starts in the main box
2. If running under `bundle exec`, re-exec into a clean Ruby process
   using Bundler.unbundled_env (prevents double gem loading)
3. Check Ruby::Box availability and enabled status
4. Switch to root box via Ruby::Box.root.eval(...)
5. Load boxwerk gem into root box ($LOAD_PATH.unshift)
6. Discover project Gemfile (gems.rb preferred, then Gemfile)
7. Run Bundler.setup + Bundler.require in root box
   → All global gems now available in root box
8. Call Boxwerk::CLI.run(ARGV)
   → CLI delegates to Setup.run! for package boot
```

### Setup.run!

```
1. Find root package.yml (walk up from current directory)
2. Create PackageResolver — discovers all package.yml files
3. Create BoxManager — manages Ruby::Box instances
4. Boot all packages in topological order (dependencies first)
```

### BoxManager.boot (per package)

For each package, in dependency order:

```
1. Create Ruby::Box.new (copied from root box, inherits global gems)
2. Setup per-package gem load paths (if Gemfile exists)
   → Prepend gem load paths to the box's $LOAD_PATH
3. Build file index — scan lib/ and public/ for .rb files
   → Map file paths to constant names using Ruby naming conventions
4. Register autoload entries in the box
   → autoload :Invoice, "/path/to/public/invoice.rb"
5. Wire dependency constants via const_missing
   → Install a resolver that searches direct dependency boxes
```

## Constant Resolution

Constants are resolved through two mechanisms:

### Intra-Package: autoload

Each package's own constants are registered as `autoload` entries in its box. When code inside the box references `Calculator`, Ruby's built-in `autoload` loads the file and defines the constant — standard Ruby behaviour.

### Cross-Package: const_missing

When a constant is not found in the current box (no autoload entry), `Object.const_missing` fires. Boxwerk installs a custom handler per-box that:

1. Iterates through the package's declared direct dependencies
2. For each dependency, checks if it has the constant (via file index or `const_get`)
3. Enforces privacy rules (public path, private_constants list)
4. Returns the constant value from the dependency's box
5. Raises `NameError` if no dependency has the constant

```ruby
# Simplified const_missing flow:
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

Constants are **not** wrapped in namespaces. `Invoice` is accessible as `Invoice`, not `Finance::Invoice`. This matches how constants work within a single Ruby application.

### Root Box Resolver (for exec/run)

When running commands via `boxwerk exec` or `boxwerk run`, some tools (like Rake) load files via the root box rather than the package box. Boxwerk installs a composite resolver on `Ruby::Box.root` that:

1. Tries the target package's own box first (for internal constants)
2. Falls through to the target box's dependency resolver
3. This ensures package constants are accessible even when code is loaded by tools running in the root box

## Package Resolution

`PackageResolver` discovers packages by scanning for `package.yml` files:

1. Start from the root `package.yml` (the root package, named `.`)
2. Glob for all `package.yml` files in subdirectories
3. Parse each YAML file into a `Package` object
4. Validate no circular dependencies exist
5. Provide topological ordering for boot (dependencies before dependents)

### package.yml Format

```yaml
enforce_dependencies: true
dependencies:
  - packs/util
  - packs/billing
enforce_privacy: true
public_path: public/          # default
private_constants:
  - "::InternalHelper"
```

This is the standard [Packwerk](https://github.com/Shopify/packwerk) format.

## Privacy Enforcement

`PrivacyChecker` enforces which constants a package exposes:

- **public_path** (default: `public/`) — Files in this directory define the package's public API. Only these constants are accessible to dependents.
- **private_constants** — Explicitly private constants, blocked even if in the public path.
- **pack_public sigil** — Files outside the public path can be marked public with `# pack_public: true` in the first 5 lines.

Privacy is checked at constant resolution time in the `const_missing` handler. A `NameError` with a descriptive message is raised for violations.

## Per-Package Gem Isolation

`GemResolver` enables different packages to use different versions of the same gem:

1. Check if the package has a `gems.rb` or `Gemfile` (and corresponding lockfile)
2. Parse the lockfile with `Bundler::LockfileParser` to get gem specs
3. Find the actual gem installation paths by searching all `Gem.path` directories
4. Collect full require paths for each gem and its runtime dependencies
5. Prepend these paths to the box's `$LOAD_PATH`

Since each box has its own `$LOAD_PATH`, `require 'faker'` in two different boxes can load different versions.

## File-to-Constant Mapping

Boxwerk maps file paths to constant names using Ruby naming conventions:

```
lib/calculator.rb      → Calculator
lib/tax_calculator.rb  → TaxCalculator
public/invoice.rb      → Invoice
lib/api/v2/client.rb   → Api::V2::Client
```

The `Boxwerk.camelize` method converts snake_case to CamelCase. For nested constants, parent modules are created as empty `Module.new` instances, and `autoload` is registered on the innermost parent.

## CLI Commands

The CLI (`Boxwerk::CLI`) provides:

| Command | Description |
|---------|-------------|
| `exec`  | Run a command (gem binstub) in the boxed environment |
| `run`   | Run a Ruby script in a package box |
| `console` | Start an IRB console in a package box |
| `info`  | Show package structure and dependencies |
| `install` | Bundle install for all packages |

### console Implementation

Console always runs IRB in `Ruby::Box.root` rather than the target package box. The composite resolver installed on root provides the same constant access. This avoids a Ruby 4.0.1 GC bug where running IRB in child boxes with `const_missing` overrides triggers a double-free crash during process exit.

### exec Implementation

`exec` resolves the command to a gem binstub path, then evaluates the binstub's content in the target box using `box.eval(content)`. File content is evaluated directly (not via `load`) because `load` creates a new file scope where inherited DSL methods (e.g. Rake's `task`) may not be visible inside a `Ruby::Box`.

### --all Flag

The `--all` flag runs `exec` for each package in a separate subprocess. This is necessary because test frameworks like Minitest register tests globally via `at_exit`, which would conflict across packages in a single process.

### --root-box Flag

The `--root-box` / `-r` flag runs commands directly in `Ruby::Box.root`, bypassing package resolution entirely. No package constants are accessible — only global gems. Useful for debugging.

## Module Structure

```
Boxwerk
├── CLI              # Command-line interface
├── Setup            # Boot orchestration (find root, create resolver + manager)
├── PackageResolver  # Discover packages, validate deps, topological sort
├── Package          # Data class for a single package
├── BoxManager       # Create boxes, build file indexes, wire constants
├── ConstantResolver # Install const_missing handlers per-box
├── PrivacyChecker   # Check public/private constant access
├── GemResolver      # Resolve per-package gem load paths
└── .camelize        # File path → constant name conversion
```
