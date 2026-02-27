# Future Improvements

This document outlines planned improvements and design considerations for Boxwerk.

## Zeitwerk Autoloading Inside Boxes

**Current limitation:** Zeitwerk's autoloading does NOT work inside `Ruby::Box` because:

1. Zeitwerk registers `const_missing` hooks on `Module` in the main context
2. Inside a box, `Module` references the box's copy, not the main one
3. The hooks never fire for constants referenced inside boxes

Boxwerk works around this by scanning files at boot time and registering
`autoload` entries directly in each box. This works but means Zeitwerk
features (reloading, eager loading, inflections) are unavailable.

### Plan

**Short term:** Improve Boxwerk's file scanner to support more Zeitwerk
features:
- Custom inflections via a Boxwerk config (e.g. `boxwerk.yml`)
- Collapse directories (Zeitwerk's `collapse` equivalent)
- Ignore paths (Zeitwerk's `ignore` equivalent)

**Medium term:** If `Ruby::Box` gains the ability to share or inherit
`const_missing` hooks from the root box, Zeitwerk could work natively inside
boxes. This would require Ruby core changes:
- `Ruby::Box.new(inherit_const_missing: true)` or similar
- Per-box Zeitwerk loader registration

**Long term:** Contribute to Ruby core to make `Ruby::Box` Zeitwerk-compatible.
This would enable full Rails autoloading inside boxes with no workarounds.

## IRB Console Improvements

**Current limitation:** The IRB console runs in a package box context with
autocomplete disabled (`--noautocomplete`). Autocomplete is disabled because
it uses `Module.constants` which doesn't reflect box-scoped constants.

### Plan

**Phase 1: Better constant discovery**
- Implement a `constants` method on each box that returns all accessible
  constants (own + dependency constants)
- Expose this via a helper: `Boxwerk.available_constants`

**Phase 2: IRB integration**
- Create a custom IRB completion proc that queries Boxwerk's constant index
  instead of using `Module.constants`
- Register it via `IRB::InputCompletor` or the newer `IRB::Completion` API
- This would allow re-enabling autocomplete with box-aware completions

## Constant Reloading

**Current limitation:** Constants loaded into a box are permanent — there's
no way to "unload" them. This means development requires restarting the
process after code changes.

### Plan

**Approach 1: Box recreation**
- Watch for file changes (using `listen` gem or `rb-fsevent`)
- When a file changes, identify which package it belongs to
- Recreate that package's box and all boxes that depend on it
- Re-wire dependency constants

This is the most correct approach but potentially expensive for large
dependency graphs. Optimizations:
- Only recreate boxes in the affected dependency subgraph
- Cache unchanged file indexes
- Use checksums to detect actual code changes vs. touch-only saves

**Approach 2: Constant removal + re-require**
- Track which constants were loaded from each file
- On file change, remove those constants from the box (`remove_const`)
- Re-require the changed file

This is faster but fragile — it doesn't handle cases where constants
reference each other or where class/module reopening has side effects.

**Approach 3: Ruby::Box API**
- If Ruby core adds a `Box#reload` or `Box#remove_const` API, use it
- This would be the cleanest solution but depends on Ruby development

**Recommended path:** Start with Approach 1 (box recreation) behind an
opt-in flag. It's correct by construction and the performance cost is
acceptable for development workflows.

## Global Gems

Currently, gems in the root `Gemfile`/`gems.rb` are loaded into the root box
via Bundler and accessible globally. Per-package gems are loaded into
individual boxes via `$LOAD_PATH` manipulation.

### Approach 1: Root Box Inheritance (Current)

Gems loaded in the root box are available in all boxes because `Ruby::Box.new`
creates a copy of the root box. The `boxwerk` executable runs `Bundler.setup`
and `Bundler.require` inside the root box before creating any child boxes.
This means:

- Gems required before box creation are available everywhere
- The root `Gemfile`/`gems.rb` acts as a "global" gem set
- Per-package `Gemfile`/`gems.rb` provides additional isolated gems

**Limitation:** Gems required after box creation are NOT shared. The order of
operations matters.

### Approach 2: Shared Gem Box

Create a dedicated "gems" box at the bottom of the dependency tree that all
packages depend on:

```
                    ┌──────────┐
                    │  gems    │  ← Contains all shared gems
                    │  (box)   │
                    └────┬─────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
         ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐
         │ billing │ │  auth  │ │  util  │
         └────────┘ └────────┘ └────────┘
```

**Benefits:**
- Explicit control over which gems are shared
- Packages can opt out of shared gems entirely (pure isolation)
- A package with no gem dependencies gets a truly clean box
- Easier to reason about gem visibility

**Rails consideration:** Rails and its dependencies are large and typically
needed across all packages. In the shared gem box approach, Rails would be
loaded into the shared gem box. Each package would inherit Rails through its
dependency on the shared gem box. Monkey patches applied by Rails gems (e.g.
ActiveSupport core extensions) would be isolated to the shared gem box and
inherited by child boxes — consistent with how root box inheritance works
today.

### Global vs Package Gem Conflicts

When a global gem (root `Gemfile`/`gems.rb`) and a package gem specify the
same gem at different versions, the package's `$LOAD_PATH` entries take
precedence because they're prepended. However, this can cause subtle issues
if the global version was already required.

**Planned resolution:**
- `boxwerk install` should detect conflicts between global and package gems
- If the same gem appears in both root and a package at different versions,
  emit a warning or error
- Explicitly prevent packages from overriding a global gem — if you need a
  different version, remove it from the global `Gemfile`/`gems.rb`
- Consider a `--strict` flag that errors on any overlap

### Package Gem Transitive Dependencies

Per-package gems should not be transitively accessible. If `packs/billing`
depends on `stripe` via its `Gemfile`/`gems.rb`, packages that depend on
`packs/billing` should not automatically get access to `stripe`.

**Current behaviour:** `$LOAD_PATH` manipulation means any package that
includes `packs/billing` as a dependency could potentially `require 'stripe'`
because the load paths are inherited via the box.

**Planned fix:**
- Only add per-package gem load paths to that package's box, not to boxes
  that depend on it
- If a dependent package also needs `stripe`, it should declare it in its
  own `Gemfile`/`gems.rb`

### Considerations

- **Native extensions:** Work per-box but may have global state (C-level
  globals) that leaks across boxes. This needs investigation.
- **Bundler integration:** Currently we parse lockfiles with
  `Bundler::LockfileParser` at boot (no subprocess). For a shared gem approach,
  we'd need to resolve a combined lockfile or use the root lockfile.

### Bundler Inside Package Boxes

Currently, per-package gems are resolved via lockfile parsing and `$LOAD_PATH`
manipulation. Gems must be manually `require`'d in pack code. This is a
significant limitation compared to normal Bundler usage.

**Goal:** Run Bundler inside each package box to properly require gems, just
like a normal Ruby application booted with Bundler.

**Benefits:**
- `require: false` in `Gemfile` would work naturally
- Gem groups (`:test`, `:development`) would be respected
- Automatic requiring of gems (Bundler.require) per package
- Per-package test/dev gems (e.g. a pack could have its own test gems)

**Approach:**
1. After creating a package's box, check for a `Gemfile`/`gems.rb`
2. Inside the box, run `Bundler.setup` with the package's Gemfile
3. Optionally `Bundler.require` for the relevant groups
4. This replaces the current `$LOAD_PATH` manipulation

**Challenges:**
- Bundler's `setup` modifies `$LOAD_PATH` globally — in a box this would
  only affect that box's `$LOAD_PATH` (desired behaviour)
- Multiple Bundler instances running in different boxes may conflict
- Need to test whether `Bundler.setup` works correctly inside `Ruby::Box`

## Alternative exec via RUBYOPT

**Status: NOT RECOMMENDED**

An alternative to the current in-process `box.eval()` approach for
`boxwerk exec` would be to set `RUBYOPT=-rboxwerk` and spawn a subprocess.

**Why it won't work:** Ruby::Box isolation exists entirely within a single
process. Each `Ruby::Box.new` creates a separate constant namespace within
that process. A spawned subprocess would create a new box tree with empty
state — the wired dependency graph, file indices, and `const_missing`
handlers cannot transfer across process boundaries. The current in-process
approach is correct by design.

## Bundler-Inspired Commands

- **`boxwerk check`** — Verify that all cross-package constant accesses match
  declared dependencies. Scan source files statically and report violations
  without running code. Useful in CI.

- **`boxwerk list`** — Display all packages, their dependencies, and their
  isolated gem dependencies. Shows the full package graph with per-package gem
  versions and highlights version differences.

- **`boxwerk package init [path]`** — Scaffold a new package with
  `package.yml`, `lib/`, `public/`, and `test/` directories. Prompts for
  dependencies and privacy settings.

- **`boxwerk outdated`** — Check for outdated gems in all package lockfiles.
  Similar to `bundle outdated` but respects package isolation — shows which
  versions each package can safely upgrade to independently.

- **`boxwerk update [package]`** — Update lockfiles for one or all packages.
  Without arguments, updates all lockfiles in topological order. With a
  package argument, updates only that package's dependencies.

- **`boxwerk clean`** — Remove unused lockfiles and empty package directories
  after packages are deleted. Warn about packages with no public constants.

## Packwerk-Inspired Features

- **Runtime Violation Recording** — Track allowed violations with structured
  metadata (violation type, constant, referencing file). Support
  `package_todo.yml` to tolerate existing violations while preventing new ones.
  Enables gradual enforcement for existing codebases.

- **Configurable Violation Handling** — Support `warn`/`strict`/`log` modes
  per package. `enforce_dependencies: warn` would log violations without
  raising, supporting gradual adoption in legacy systems.

- **Violation Context & Suggestions** — When a violation occurs, provide
  actionable context in the NameError message — show the required dependency
  declaration and suggest the `package.yml` change needed to fix it.

- **Custom Runtime Checkers** — Allow plugins to define additional constraint
  checks beyond dependencies and privacy (e.g. restrict cross-cutting
  concerns, enforce max package size).

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## IDE Support

- Language servers could be aware of package boundaries
- Autocomplete could filter to only accessible constants
- Privacy violations could be highlighted in real-time
