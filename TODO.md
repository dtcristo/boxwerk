# TODO

Planned improvements for Boxwerk, ordered by priority.

## Summary

| # | Item | Priority | Status |
|---|------|----------|--------|
| 1 | `boxwerk-rails` gem | Medium | Future |
| 2 | Constant reloading (dev workflow) | Medium | Not started |
| 3 | IRB console autocomplete | Medium | Not started |
| 4 | `boxwerk init` (scaffold packages) | Low | Not started |
| 5 | Sorbet support | Low | Future |
| 6 | Per-package testing improvements | Low | Not started |
| 7 | Additional CLI commands | Low | Not started |
| 8 | IDE / language server support | Low | Future |
| 9 | Bundler inside package boxes | — | Blocked (Ruby::Box) |
| 10 | RUBYOPT bootstrap | — | Blocked (Ruby::Box) |

---

## 1. `boxwerk-rails` Gem

**Priority: Medium — Future**

A companion gem that automatically configures Rails for Boxwerk. Would
eliminate manual setup in `global/boot.rb` and `bin/rails`.

### Scope

- Auto-configure `config.autoload_paths = []` and `config.eager_load_paths = []`
- Create a `bin/rails` binstub compatible with `boxwerk exec`
- Pre-require and eager-load Rails frameworks in global boot
- Aggregate migration paths from packages (`packs/*/db/migrate/`)
- Package-aware Rails generators

### Prerequisites

- Per-package gem auto-require — needed for clean gem loading ✅
- `Boxwerk.package` API — needed for package-aware generators ✅
- Stable Boxwerk API

---

## 2. Constant Reloading

**Priority: Medium**

Constants loaded into a box are permanent. Development requires restarting
the process after code changes.

### Plan

**Approach 1: Box recreation (recommended)**
- Watch for file changes (`listen` gem or `rb-fsevent`)
- When a file changes, identify the owning package
- Recreate that package's box and all dependent boxes
- Re-wire dependency constants

Optimizations: only recreate the affected subgraph, cache unchanged indexes,
use checksums to skip touch-only saves.

**Approach 2: Ruby::Box API**
- A future `Box#reload` or `Box#remove_const` API would be ideal

Start with Approach 1 behind an opt-in flag (`boxwerk run --watch`).

---

## 3. IRB Console Autocomplete

**Priority: Medium**

`boxwerk console` runs with `--noautocomplete` because IRB's completer uses
`Module.constants` which doesn't reflect box-scoped constants.

Console runs in `Ruby::Box.root` with a composite resolver (workaround for a
Ruby 4.0.1 GC crash in child boxes). Revisit when Ruby::Box stabilizes.

### Plan

1. Implement `Boxwerk.available_constants(box)` — returns own + dependency
   constants for a box
2. Create a custom IRB completion proc querying the Boxwerk constant index
3. Register via `IRB::Completion` API

---

## 4. `boxwerk init`

**Priority: Low**

Scaffold a new package with `package.yml`, `lib/`, `public/`, and `test/`.

---

## 5. Sorbet Support

**Priority: Low — Future**

Enable Sorbet type-checking across Boxwerk package boundaries. Types defined
in one package should be visible to dependents according to the same rules as
runtime constants.

### Possible Approaches

- **Custom Tapioca Compiler** — Generate RBI files per package that reflect
  the dependency graph. Only expose types from declared dependencies.
- **Plugin gem** (`boxwerk-sorbet` or `sorbet-boxwerk`) — Integrate with
  Sorbet's plugin system to enforce package boundaries at type-check time.
- **RBI generation from file indexes** — Use Boxwerk's existing file index
  and privacy checker to generate per-package RBI files.

### Challenges

- Sorbet expects all constants in a flat namespace; Boxwerk's box isolation
  is invisible to the type checker
- Need to map Boxwerk's runtime `const_missing` resolution to static types
- Privacy enforcement must work at both type-check and runtime

---

## 6. Per-Package Testing Improvements

**Priority: Low**

Tests currently run via `boxwerk exec --all rake test` with subprocess
isolation.

### Possible Improvements

- **Parallel execution** — run package tests in parallel for faster CI
- **Coverage aggregation** — merge coverage reports across packages

---

## 7. Additional CLI Commands

**Priority: Low**

- **`boxwerk outdated`** — check for outdated per-package gems
- **`boxwerk update [package]`** — update lockfiles in topological order
- **`boxwerk clean`** — remove unused lockfiles and empty directories
- **`boxwerk list`** — display packages with gem versions

---

## 8. IDE / Language Server Support

**Priority: Low — Future**

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Go-to-definition across package boundaries (respecting privacy)
- Real-time privacy violation highlighting

---

## 9. Bundler Inside Package Boxes

**Status: Blocked (Ruby::Box limitation)**

`Bundler.setup` inside a child box modifies the ROOT box's `$LOAD_PATH`
because Bundler's code is defined in the root box. Current workaround:
parse lockfiles and manipulate `$LOAD_PATH` directly.

Requires Ruby::Box changes to support Bundler running in child box context.

---

## 10. RUBYOPT Bootstrap (`-rboxwerk/setup`)

**Status: Blocked (Ruby::Box limitation)**

Set `RUBYOPT=-rboxwerk/setup` to automatically bootstrap without `boxwerk
exec`. Multiple Ruby::Box limitations prevent this:

- `$LOAD_PATH` is per-box and isolated
- `require` in `Ruby::Box.root.eval` fails in RUBYOPT context
- Zeitwerk's `Kernel.require` patch runs in root box context
- Global gems would load multiple times

A proof-of-concept worked for packages without per-package gems. Full support
requires Ruby::Box API improvements (shared `$LOAD_PATH`, main box
redirection, Zeitwerk box-awareness).

---

## Done

Items completed and removed from active tracking:

- ✅ **Zeitwerk integration** — File scanning, inflection, `autoload_dirs`,
  `collapse_dirs`, eager loading. Remaining: `ignore_dirs` consumption,
  reloading (see #2).
- ✅ **Rails integration** — Rails 8.1 API app, Puma, ActiveRecord,
  ActionController, foundation pattern, privacy enforcement. See
  [examples/rails/](examples/rails/).
- ✅ **Global gems** — Root `Gemfile` gems loaded in root box, inherited by
  all child boxes via snapshot. Version conflict warnings.
- ✅ **Per-package gem auto-require** — Gems auto-required matching
  Bundler behaviour. `require: false` and custom require paths supported.
- ✅ **`Boxwerk.package` API** — `PackageContext` with autoloader config.
- ✅ **Improved NameError messages** — Privacy and non-dependency hints.
- ✅ **Rails e2e tests moved** — To `examples/rails/test/e2e_test.rb`.
- ✅ **Monkey patch isolation** — Kitchen example with integration test.
- ✅ **Rails in root package** — Eager-load Rails in global/boot.rb,
  initialize in root package boot.rb. `-g` no longer needed for Rails commands.
- ✅ **Remove Rails special-casing** — Generic `bin/<command>` lookup
  replaces `execute_rails_command`. Rails example uses standard `bin/rails`.
