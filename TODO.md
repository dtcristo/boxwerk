# TODO

Planned improvements and design considerations for Boxwerk.

## Summary

| Item | Priority | Complexity |
|------|----------|------------|
| Zeitwerk full integration (reloading, eager loading) | Medium | Hard |
| Constant reloading (dev workflow) | High | Hard |
| Bundler inside package boxes | High | Medium |
| Gem group support (`:test`, `:development`) | High | Medium |
| RUBYOPT bootstrap (`-rboxwerk/setup`) | High | Blocked (Ruby::Box) |
| Per-package testing (`boxwerk test`) | Medium | Medium |
| IRB console autocomplete | Medium | Medium |
| Global vs package gem conflict detection | Medium | Easy |
| Package gem transitive dependency isolation | Medium | Medium |
| `boxwerk check` (static analysis) | Medium | Medium |
| `boxwerk init` (scaffold packages) | Low | Easy |
| `boxwerk list` / `boxwerk outdated` / `boxwerk update` | Low | Easy |
| `boxwerk clean` | Low | Easy |
| Automatic version switching | Low | Easy |
| Configurable violation handling (warn/strict) | Low | Easy |
| package_todo.yml support | Low | Medium |
| IDE / language server support | Low | Hard |
| Rails integration | High | Hard |

## Zeitwerk Full Integration

**Current state:** Boxwerk uses Zeitwerk for file scanning and inflection. The
`ZeitwerkScanner` module creates a temporary `Zeitwerk::Loader` to scan
directories, then registers autoloads directly in each box via `box.eval`.

This gives us Zeitwerk's file discovery conventions and inflection rules, but
not Zeitwerk's runtime features (reloading, eager loading, callbacks).

**Why not full Zeitwerk?** Zeitwerk's `autoload` calls execute in the root box
context (where Zeitwerk was loaded), not the target package box. Ruby::Box
scopes autoloads per-box, so autoloads registered by Zeitwerk are invisible
in child boxes. The `const_added` callback has the same problem.

### Remaining Work

- **Custom inflections** — Forward custom inflection config to the Zeitwerk
  inflector (e.g. acronyms like `HTML`, `API`)
- **Collapse directories** — Support Zeitwerk's `collapse` equivalent
- **Ignore paths** — Support Zeitwerk's `ignore` equivalent
- **Eager loading** — Implement `box.eval(File.read(file))` for all files
  to support production eager loading
- **Reloading** — Would require recreating boxes (see Constant Reloading below)

**Long term:** If `Ruby::Box` gains the ability to specify the box context for
autoload registration, full Zeitwerk integration becomes possible.

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

**Note:** Console runs IRB in `Ruby::Box.root` (with the composite resolver)
instead of the target package box. This works around a Ruby 4.0.1 GC crash
(`_box_entry_free` double-free during process exit) triggered by running IRB
in child boxes with `const_missing` overrides. This should be revisited when
Ruby::Box stabilizes.

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

**Status:** Blocked (Ruby::Box limitation)

Currently per-package gems are resolved via lockfile parsing and manual
`$LOAD_PATH` manipulation. This approach works but has limitations.

**Investigation findings:**
- `Bundler.setup` inside a child box modifies the ROOT box's `$LOAD_PATH`
  (not the child's) because Bundler's code is defined in the root box
- `require 'bundler/setup'` inside `box.eval` has no effect on `$LOAD_PATH`
- `require 'bundler'; Bundler.setup` partially works (modifies root LP) but
  doesn't help the child box
- `Bundler::Definition.build` can extract gem paths from root context but
  that's equivalent to our current lockfile parsing approach

**Current approach (working):**
1. Parse lockfile with `Bundler::LockfileParser`
2. Resolve gem specs via `Gem::Specification`
3. Add load paths to child box's `$LOAD_PATH` directly
4. Detect global-vs-package version conflicts at boot time

**What this means:**
- `require: false` in per-package Gemfile does NOT prevent auto-loading
  (all lockfile gems are added to `$LOAD_PATH`)
- Gem groups (`:test`, `:development`) are not respected
- `Bundler.require` per package is not possible

**Future:** Requires Ruby::Box changes to support Bundler running in child
box context, or a fundamentally different approach to gem loading.

### Automatic Version Switching

When `boxwerk` is installed globally (or via a different version than the
project's Gemfile specifies), auto-detect the mismatch and re-exec with the
correct version. Similar to how `rbenv`/`mise` handle Ruby version switching.

**Approach:** Check `Gem.loaded_specs["boxwerk"]` against the project's
lockfile version. If they differ, re-exec via `Bundler.with_unbundled_env`
using the correct gem path.

## Gem Group Support

**Current limitation:** All gems in a package's lockfile are added to
`$LOAD_PATH` regardless of groups. `Bundler.require` cannot run inside
child boxes (see "Bundler Inside Package Boxes" above).

Global gems in the root Gemfile work with groups normally (Bundler runs in
the root box). Per-package gems are always available once resolved.

**Blocked by:** Bundler Inside Package Boxes.

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

## RUBYOPT Bootstrap

**Status: Not feasible with Ruby 4.0.** Multiple Ruby::Box limitations prevent
a reliable RUBYOPT-based bootstrap. Documented here for future reference.

**Idea:** Set `RUBYOPT=-rboxwerk/setup` to automatically bootstrap the Boxwerk
environment for any Ruby process. `ruby app.rb`, `rake test`, `rails console`
would all run inside the boxed environment without `boxwerk exec`.

### Investigation Results

Extensive prototyping revealed several interacting Ruby::Box limitations that
make this approach unreliable:

**1. `$LOAD_PATH` is per-box and isolated.**
Changes to root box's `$LOAD_PATH` are invisible to main box and vice versa.
`Bundler.setup` adds gem paths to the calling box only. This means setting up
Bundler in root box doesn't help main box resolve gems.

**2. `require` in `Ruby::Box.root.eval` fails in RUBYOPT context.**
The same `require 'zeitwerk'` call that works when run inline (not via `-r`)
fails with `LoadError` when triggered from a RUBYOPT-loaded file, even with
zeitwerk on root's `$LOAD_PATH`. The box loader (`Ruby::Box::Loader#require`)
behaves differently in the RUBYOPT context. `Kernel.require` (bypassing the
box loader) works, but `load` with full paths is the only reliable method.

**3. Zeitwerk's `Kernel.require` patch runs in root box context.**
Zeitwerk patches `Kernel#require` globally. When a file loaded via
`box.require(file)` calls `require 'some_gem'`, the call dispatches through
zeitwerk's patch in root box context. If the gem isn't on root's `$LOAD_PATH`,
it fails — even if it's on the child box's `$LOAD_PATH`.

**4. Global gems would load multiple times (memory bloat).**
The `boxwerk exec` approach loads global gems once in root box before creating
child boxes (which inherit via copy-on-write). With RUBYOPT, there's no way to
ensure gems load in root box first. Each child box would `require` global gems
independently, duplicating them in memory — defeating the purpose of the root
box inheritance model.

**5. `Bundler.setup` introduces nil `$LOAD_PATH` entries.**
In RUBYOPT context, `Bundler::SharedHelpers#clean_load_path` crashes on nil
entries in `$LOAD_PATH` that Ruby::Box introduces. Workaround exists
(`$LOAD_PATH.reject!(&:nil?)`) but indicates fragile interaction.

### Partial Success

A proof-of-concept *did* work for packages without per-package gems:

```ruby
# const_missing on main's Object delegates to root package box
Ruby::Box.root.eval("require 'boxwerk'; Boxwerk::Setup.run!(...)")
$BOXWERK_ROOT_PKG_BOX = Ruby::Box.root.eval("Boxwerk::Setup.root_box")
class Object
  def self.const_missing(name)
    $BOXWERK_ROOT_PKG_BOX.eval(name.to_s)
  rescue NameError
    raise NameError, "uninitialized constant #{name}"
  end
end
```

This resolved constants, enforced privacy, and blocked transitive access.
It failed only when child box code called `require` for per-package gems.

### Why This Matters (If Solved)

- **No `boxwerk exec` needed.** Plain `ruby app.rb` just works.
- **Composable with any tool.** `rails console`, `rspec`, `rubocop` run
  inside the boxed environment without wrappers.
- **No re-implementing commands.** Standard Bundler/Rails commands work
  directly with Boxwerk providing isolation transparently.

### What Would Make This Possible

- **Ruby::Box API for shared `$LOAD_PATH`** — or a way to specify that
  `require` calls should resolve against a specific box's load path.
- **Ruby::Box API for main box redirection** — ability to redirect main
  box execution into a child box.
- **Zeitwerk box-awareness** — Zeitwerk's `Kernel.require` patch would need
  to resolve against the calling box's `$LOAD_PATH`, not root's.

Until Ruby::Box matures with these capabilities, `boxwerk exec` remains the
correct approach for bootstrapping the boxed environment.

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## IDE Support

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Real-time privacy violation highlighting
- Go-to-definition across package boundaries (respecting privacy)
