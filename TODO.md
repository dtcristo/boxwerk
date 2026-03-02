# TODO

Planned improvements for Boxwerk, ordered by priority.

## Summary

| # | Item | Priority | Status |
|---|------|----------|--------|
| 7 | `boxwerk-rails` gem | Medium | Future |
| 8 | Fix `rails console` crash | Medium | Not started |
| 14 | Constant reloading (dev workflow) | Medium | Not started |
| 15 | IRB console autocomplete | Medium | Not started |
| 16 | `boxwerk init` (scaffold packages) | Low | Not started |
| 17 | Sorbet support | Low | Future |
| 18 | Per-package testing improvements | Low | Not started |
| 19 | Additional CLI commands | Low | Not started |
| 20 | IDE / language server support | Low | Future |
| 21 | Bundler inside package boxes | Low | Investigated — current approach preferred |
| 22 | RUBYOPT bootstrap (multi-phase) | Medium | Future |
| 23 | Native Zeitwerk autoloaders in resolution | Medium | Investigated — partially feasible |

---

## 7. `boxwerk-rails` Gem

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

## 8. Fix `rails console` Crash

**Priority: Medium**

`boxwerk exec rails console` crashes when you type input. This is likely due to IRB/readline interaction with Ruby::Box context. The workaround is to use `boxwerk console` instead, which properly handles the console environment.

### Implementation Plan

1. **Investigate** — Reproduce the crash, check if it's a readline/reline issue in box context.
2. **If fixable** — Fix the interaction between `rails/commands` console mode and box eval.
3. **If not easily fixable** — Document `boxwerk console` as the recommended interactive console. Rails console docs already updated in `examples/rails/README.md`.

---

## 14. Constant Reloading

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

## 15. IRB Console Autocomplete

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

## 16. `boxwerk init`

**Priority: Low**

Scaffold a new package with `package.yml`, `lib/`, `public/`, and `test/`.

---

## 17. Sorbet Support

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

## 18. Per-Package Testing Improvements

**Priority: Low**

Tests currently run via `boxwerk exec --all rake test` with subprocess
isolation.

### Possible Improvements

- **Parallel execution** — run package tests in parallel for faster CI
- **Coverage aggregation** — merge coverage reports across packages

---

## 19. Additional CLI Commands

**Priority: Low**

- **`boxwerk outdated`** — check for outdated per-package gems
- **`boxwerk update [package]`** — update lockfiles in topological order
- **`boxwerk clean`** — remove unused lockfiles and empty directories
- **`boxwerk list`** — display packages with gem versions

---

## 20. IDE / Language Server Support

**Priority: Low — Future**

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Go-to-definition across package boundaries (respecting privacy)
- Real-time privacy violation highlighting

---

## 21. Bundler Inside Package Boxes

**Priority: Low — Current lockfile-parsing approach works well**

**Status: Investigated; current approach preferred over native Bundler**

### Investigation Results

Two approaches were tested for native `Bundler.setup` inside child boxes:

#### Approach 1: Box-Local Monkey-Patch

The original plan was to eval Bundler patches inside child boxes. However, `require 'bundler'` inside a child box loads Bundler's code into that box, but Bundler internally calls back into root-box code (e.g., `Gem` activation, `$LOAD_PATH` modification). **Bundler's code architecture makes surgical patching impractical** — too many internal methods would need overriding.

#### Approach 2: Capture-and-Apply

Run `Bundler.setup` in the root box with the package's gemfile, capture the `$LOAD_PATH` delta, restore root state, and apply the delta to the child box. This was tested and **works**:

```ruby
# Capture new paths from Bundler.setup
before = $LOAD_PATH.dup
ENV['BUNDLE_GEMFILE'] = pkg_gemfile
Bundler.reset!
Bundler.setup
new_paths = $LOAD_PATH - before
$LOAD_PATH.replace(before)  # restore
```

However, this approach has significant drawbacks:
- **Temporarily mutates root `$LOAD_PATH`** — requires careful save/restore
- **`Bundler.reset!` has side effects** — global Bundler state is modified
- **Serial execution required** — can't parallelize Bundler.setup calls
- **GC crashes** — Ruby::Box + Bundler interaction triggers known Ruby 4.0.1 GC bug ("pointer being freed was not allocated") on exit
- **No clear advantage** — produces the same result as lockfile parsing

### Conclusion

The current `GemResolver` lockfile-parsing approach is **simpler, more reliable, and produces identical results**. It parses `gems.locked`/`Gemfile.lock` with `Bundler::LockfileParser`, resolves gem specs via `Gem.path`, and collects load paths recursively. This avoids all Bundler runtime side effects.

Native `Bundler.setup` integration should only be revisited if:
- Ruby::Box gains native Bundler support
- The GC crash bug is fixed
- A use case emerges that lockfile parsing can't handle

---

## 22. RUBYOPT Bootstrap (`-rboxwerk/setup`)

**Priority: Medium — Future**

**Status: Previously blocked; revisited for box-local monkey-patching**

Using `RUBYOPT=-rboxwerk/setup` to automatically bootstrap hits obstacles with gem loading and Zeitwerk handling. Box-local monkey-patching can help:

### Box-Local Monkey-Patch Approach

When RUBYOPT loads `boxwerk/setup`:

1. **Bootstrap minimal setup** — Detect Ruby::Box, activate it, call `Boxwerk::Setup.run` from root box to boot all packages
2. **Bundler patches in package boxes** — When package boxes are created, inject Bundler patches (from item 21) so native gem loading works
3. **Zeitwerk patches in package boxes** — Inject Zeitwerk patches so `Kernel.require` and autoload work in correct box context

This is feasible because patches are box-local and don't interfere with each other.

### Implementation Plan

1. **Create `lib/boxwerk/setup.rb`** (RUBYOPT entry point) — Minimal bootstrap that:
   - Checks Ruby::Box availability
   - Switches to root box
   - Requires Boxwerk lib
   - Calls `Boxwerk::Setup.run`
2. **Reuse item 21 patches** — Bundler patches from item 21 are automatically applied in package boxes during boot
3. **Create `lib/boxwerk/patches/zeitwerk.rb`** — Monkey patches for Zeitwerk if needed (may be unnecessary if Bundler alone works)
4. **Test** — RUBYOPT bootstrap with both global and per-package gems
5. **Handle edge cases** — Double-loading prevention, boot order, gem requiring

### Challenges

- Complexity of initial RUBYOPT bootstrap (but simpler if Bundler patches from item 21 work)
- Ensuring all gems load correctly without being loaded twice
- May require additional Zeitwerk patches beyond Bundler

Recommend starting with item 21 (Bundler patch). If that works, RUBYOPT becomes straightforward.

---

## 23. Native Zeitwerk Autoloaders in Constant Resolution

**Priority: Medium — Future**

**Status: Investigated; partially feasible with workaround for implicit namespaces**

Currently, Boxwerk uses Zeitwerk only for file scanning and inflection. Autoloads are registered via `box.eval("autoload :Foo, '/path'")` (manual). Native Zeitwerk autoloaders per box were tested.

### Investigation Results

#### What Works

Native `Zeitwerk::Loader` instances **work inside child boxes** for packages with real files:

```ruby
box.eval("$LOAD_PATH.unshift('#{zeitwerk_path}')")
box.eval("require 'zeitwerk'")
box.eval(<<~CODE)
  loader = Zeitwerk::Loader.new
  loader.push_dir('#{pkg_dir}', namespace: Object)
  loader.setup
CODE
box.eval('Orders::Order.name')  # => "Orders::Order" ✅
box.eval('loader.eager_load')   # ✅
```

Tested and confirmed:
- ✅ Autoload registration in child box
- ✅ Nested constant resolution (`Orders::Order`, `Orders::LineItem`)
- ✅ Eager loading
- ✅ Isolation (constants don't leak to root box)

#### What Doesn't Work: Implicit Namespaces

**Implicit namespaces fail.** When a directory exists without a matching `.rb` file (e.g., `kitchen/` without `kitchen.rb`), Zeitwerk registers an autoload pointing to the directory path. When Ruby triggers the autoload, Zeitwerk's `Kernel#require` override normally intercepts it to create the namespace module. However, **Ruby::Box replaces `Kernel#require`** with its own `Ruby::Box::Loader#require`, which doesn't know about Zeitwerk's implicit namespace convention and fails with `LoadError`.

**Workaround:** Pre-create implicit namespace modules before Zeitwerk setup:

```ruby
box.eval('module Kitchen; end')  # pre-create implicit namespace
box.eval('loader.setup')         # now Zeitwerk works ✅
```

This was tested and works, but it means Boxwerk would still need to scan directory structures to identify implicit namespaces — partially defeating the purpose of delegating to Zeitwerk.

#### Collapse Dirs

Collapse dirs with implicit namespaces also fail for the same reason. They work after pre-creating the namespace module.

### Conclusion

Native Zeitwerk is **viable but requires a pre-scan step** for implicit namespaces. This makes the integration more complex than originally hoped. The current manual autoload approach already handles implicit namespaces correctly (creates modules via `box.eval("module Foo; end")`) and is simpler.

Worth revisiting if:
- Ruby::Box adds Zeitwerk-aware require handling
- Ruby::Box exposes a hook for custom autoload resolution
- Zeitwerk adds a mode that pre-creates implicit namespace modules
