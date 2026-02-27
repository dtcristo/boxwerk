# TODO

Planned improvements and design considerations for Boxwerk.

## Summary

| Item | Priority | Complexity |
|------|----------|------------|
| Zeitwerk full integration (reloading, eager loading) | Medium | Hard |
| Constant reloading (dev workflow) | High | Hard |
| Bundler inside package boxes | High | Medium |
| Gem group support (`:test`, `:development`) | High | Medium |
| RUBYOPT bootstrap (`-rboxwerk/setup`) | High | Hard |
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

### Automatic Version Switching

When `boxwerk` is installed globally (or via a different version than the
project's Gemfile specifies), auto-detect the mismatch and re-exec with the
correct version. Similar to how `rbenv`/`mise` handle Ruby version switching.

**Approach:** Check `Gem.loaded_specs["boxwerk"]` against the project's
lockfile version. If they differ, re-exec via `Bundler.with_unbundled_env`
using the correct gem path.

## Gem Group Support

**Current limitation:** `Bundler.require` in the root box only requires the
default group. Gems in `:test` or `:development` groups are available on
`$LOAD_PATH` (via `Bundler.setup`) but not auto-required. This means gems
like `rake` must be in the default group because rake's DSL (`task`) needs
to be loaded in the root box for Rakefiles to work.

**Blocked by:** Bundler Inside Package Boxes. Once Bundler runs per-box,
`Bundler.require(:default, :test)` can be called in the appropriate context.

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

**Idea:** Set `RUBYOPT=-rboxwerk/setup` to automatically bootstrap the Boxwerk
environment for any Ruby process. This would mean `ruby app.rb`, `rake test`,
`bundle install` etc. all run inside the boxed environment without needing
`boxwerk exec` as a wrapper.

### How It Would Work

1. `boxwerk/setup` is required early via RUBYOPT (before the script loads)
2. It discovers `package.yml`, resolves packages, creates boxes
3. The script then runs inside the root package box with full isolation

### Open Questions

- **Which box does the script run in?** RUBYOPT runs in the main box (before
  any box switching). `boxwerk/setup` would need to set up boxes in the root
  box, then somehow redirect execution into the root package box. This is the
  core challenge — we can set up the environment but the user's script still
  runs in the main box unless we re-exec or use `Ruby::Box.root.eval`.

- **Process boundary.** `Ruby::Box` isolation is in-process only. Child
  processes (e.g. `bundle install` spawning subprocesses) create fresh box
  trees. However, if RUBYOPT persists, the child process would also bootstrap
  Boxwerk — this might actually be what we want.

- **Compatibility with Bundler.** If `RUBYOPT=-rbundler/setup -rboxwerk/setup`,
  load order matters. Bundler restricts `$LOAD_PATH` before Boxwerk can set up
  boxes. We may need `boxwerk/setup` to be loaded _before_ Bundler, or handle
  the case where Bundler is already active.

### Why This Matters

If RUBYOPT bootstrap works, several things simplify dramatically:

- **No `boxwerk exec` needed.** Plain `ruby app.rb` or `rake test` just works.
  Boxwerk becomes invisible infrastructure, like Bundler itself.

- **No `boxwerk install` command.** `bundle install` with RUBYOPT set would
  run in each package's context automatically — or we could simply run
  `bundle install` in each package directory and it works because RUBYOPT
  bootstraps Boxwerk for the Bundler subprocess too.

- **No re-implementing Bundler commands.** Instead of `boxwerk outdated`,
  `boxwerk update` etc., just run the standard Bundler commands. Boxwerk
  provides the isolation layer transparently.

- **Composable with any tool.** `rails console`, `rspec`, `rubocop` — all
  would run inside the boxed environment without boxwerk-specific wrappers.

### Prototype Path

1. Create `lib/boxwerk/setup.rb` that performs the full bootstrap
2. Test with `RUBYOPT=-rboxwerk/setup ruby -e "puts Invoice"`
3. Investigate whether the main box vs root box issue can be solved
4. Test with `RUBYOPT=-rboxwerk/setup bundle install` in a package directory
5. If the main box issue is a blocker, consider whether `Ruby::Box` will
   eventually support redirecting the main box's execution context

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## IDE Support

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Real-time privacy violation highlighting
- Go-to-definition across package boundaries (respecting privacy)
