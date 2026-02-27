# TODO

Planned improvements and design considerations for Boxwerk.

## Summary

| Item | Priority | Complexity |
|------|----------|------------|
| Zeitwerk autoloading inside boxes | High | Hard |
| Constant reloading (dev workflow) | High | Hard |
| Bundler inside package boxes | High | Medium |
| Per-package testing (`boxwerk test`) | Medium | Medium |
| IRB console autocomplete | Medium | Medium |
| Global vs package gem conflict detection | Medium | Easy |
| Package gem transitive dependency isolation | Medium | Medium |
| `boxwerk check` (static analysis) | Medium | Medium |
| `boxwerk init` (scaffold packages) | Low | Easy |
| `boxwerk list` / `boxwerk outdated` | Low | Easy |
| Configurable violation handling (warn/strict) | Low | Easy |
| package_todo.yml support | Low | Medium |
| IDE / language server support | Low | Hard |
| Rails integration | High | Hard |

## Zeitwerk Autoloading Inside Boxes

**Current limitation:** Zeitwerk does not work inside `Ruby::Box` because
Zeitwerk registers `const_missing` hooks on `Module` in the main box. Inside
a user box, `Module` is the box's copy — hooks from other boxes don't fire.

Boxwerk works around this by scanning files at boot and registering `autoload`
entries directly. This means Zeitwerk features (reloading, eager loading,
custom inflections) are unavailable.

### Plan

**Short term:** Extend Boxwerk's file scanner:
- Custom inflections via `boxwerk.yml`
- Collapse directories (Zeitwerk's `collapse` equivalent)
- Ignore paths (Zeitwerk's `ignore` equivalent)

**Medium term:** If `Ruby::Box` gains shared `const_missing` inheritance
(e.g. `Ruby::Box.new(inherit_const_missing: true)`), Zeitwerk could work
natively. This requires Ruby core changes.

**Long term:** Contribute upstream to make `Ruby::Box` Zeitwerk-compatible,
enabling full Rails autoloading inside boxes.

## Constant Reloading

**Current limitation:** Constants loaded into a box are permanent. Development
requires restarting the process after code changes.

### Plan

**Approach 1: Box recreation (recommended)**
- Watch for file changes (`listen` gem or `rb-fsevent`)
- When a file changes, identify the owning package
- Recreate that package's box and all dependent boxes
- Re-wire dependency constants

Optimizations: only recreate the affected subgraph, cache unchanged indexes,
use checksums to skip touch-only saves.

**Approach 2: Constant removal + re-require**
- Track constants per file, `remove_const` on change, re-require
- Fast but fragile with cross-references and class reopening

**Approach 3: Ruby::Box API**
- A future `Box#reload` or `Box#remove_const` API would be ideal

Start with Approach 1 behind an opt-in flag (`boxwerk run --watch`).

## IRB Console Improvements

**Current limitation:** `boxwerk console` runs with `--noautocomplete` because
IRB's completer uses `Module.constants` which doesn't reflect box-scoped
constants.

### Plan

1. Implement `Boxwerk.available_constants(box)` — returns own + dependency
   constants for a box
2. Create a custom IRB completion proc that queries the Boxwerk constant index
3. Register via `IRB::Completion` API to enable box-aware autocomplete

## Global Gems

Currently gems in the root `Gemfile`/`gems.rb` are loaded into the root box
via Bundler. All user boxes inherit them via copy-on-write.

### Current Approach: Root Box Inheritance

The `boxwerk` executable runs `Bundler.setup` and `Bundler.require` inside the
root box before creating any package boxes. This means:

- Gems required before box creation are available everywhere
- The root `Gemfile`/`gems.rb` acts as a "global" gem set
- Per-package `Gemfile`/`gems.rb` provides additional isolated gems
- **Limitation:** Gems required *after* box creation are not shared

### Alternative: Shared Gem Box

Create a dedicated "gems" box that all packages depend on:

```
              ┌──────────┐
              │   gems   │  ← shared gems loaded here
              └────┬─────┘
                   │
        ┌──────────┼──────────┐
        │          │          │
   ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐
   │ billing │ │  auth  │ │  util  │
   └────────┘ └────────┘ └────────┘
```

Benefits: explicit control over shared gems, packages can opt out entirely.

**Rails consideration:** Rails would be loaded into the shared gem box. Monkey
patches (e.g. ActiveSupport core extensions) would be isolated to that box and
inherited by child boxes — consistent with root box inheritance today.

### Global vs Package Gem Conflicts

When a global gem and a package gem specify different versions, the package's
`$LOAD_PATH` entries take precedence (prepended). This can cause issues if the
global version was already required.

**Planned resolution:**
- `boxwerk install` detects version conflicts between global and package gems
- Error or warn when the same gem appears at different versions
- Packages must not override global gems — use per-package gems only for
  gems not in the global set
- Consider `--strict` flag that errors on any overlap

### Package Gem Transitive Dependencies

Per-package gems should not leak to dependents. If `packs/billing` has `stripe`
in its `Gemfile`, packages depending on `packs/billing` should not get `stripe`.

**Current behaviour:** `$LOAD_PATH` manipulation is box-local, but constants
from gems required in one box may leak between boxes (a Ruby::Box limitation
with C-level global state).

**Planned fix:** Only add gem load paths to the owning package's box. Dependent
packages must declare their own gem dependencies.

### Bundler Inside Package Boxes

Currently per-package gems are resolved via lockfile parsing and `$LOAD_PATH`
manipulation. Gems must be manually `require`'d.

**Goal:** Run Bundler inside each package box for proper gem lifecycle:
- `require: false` in Gemfile works naturally
- Gem groups (`:test`, `:development`) respected
- `Bundler.require` per package for automatic requiring
- Per-package test/dev gems

**Approach:**
1. After creating a package box, check for a Gemfile
2. Run `Bundler.setup` inside the box with that package's Gemfile
3. Optionally `Bundler.require` for relevant groups

**Challenge:** Multiple Bundler instances in different boxes may conflict.
Need to test whether `Bundler.setup` works correctly inside `Ruby::Box`.

## Per-Package Testing

**Current state:** Tests run via `boxwerk exec -p packs/name rake test` or
`boxwerk exec --all rake test`. Each `--all` package runs in a subprocess for
clean isolation.

### Possible Improvements

- **`boxwerk test` command** — dedicated test runner that discovers and runs
  all package tests, with better output formatting and summary
- **Parallel execution** — run package tests in parallel (each in its own
  subprocess) for faster CI
- **Test dependency isolation** — per-package test gems via Bundler groups
  (requires "Bundler Inside Package Boxes" above)
- **Coverage aggregation** — collect and merge coverage reports across packages

## Bundler-Inspired Commands

- **`boxwerk check`** — Static analysis of cross-package constant references.
  Scan source files without running code, report dependency/privacy violations.
  Useful in CI alongside Packwerk.

- **`boxwerk list`** — Display packages, dependencies, and per-package gem
  versions. Show the full package graph with version differences highlighted.

- **`boxwerk init [path]`** — Scaffold a new package with `package.yml`,
  `lib/`, `public/`, and `test/` directories.

- **`boxwerk outdated`** — Check for outdated per-package gems. Like
  `bundle outdated` but respects package isolation.

- **`boxwerk update [package]`** — Update lockfiles for one or all packages
  in topological order.

- **`boxwerk clean`** — Remove unused lockfiles and empty package directories.

## Packwerk-Inspired Features

- **package_todo.yml** — Track allowed violations with structured metadata.
  Tolerate existing violations while preventing new ones. Enables gradual
  enforcement for existing codebases.

- **Configurable violation handling** — `warn`/`strict`/`log` modes per
  package. `enforce_dependencies: warn` logs violations without raising.

- **Violation context** — NameError messages show the required dependency
  declaration and suggest the `package.yml` change needed.

- **Custom checkers** — Plugin API for additional runtime constraints beyond
  dependencies and privacy.

## Alternative exec via RUBYOPT

**Status: NOT RECOMMENDED**

Setting `RUBYOPT=-rboxwerk` and spawning a subprocess won't work. Ruby::Box
isolation is in-process only — a subprocess creates a fresh box tree. The
wired dependency graph cannot transfer across process boundaries.

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## IDE Support

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Real-time privacy violation highlighting
- Go-to-definition across package boundaries (respecting privacy)
