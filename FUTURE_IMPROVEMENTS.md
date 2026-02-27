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

**Current limitation:** The IRB console runs in the root box context with
autocomplete disabled (`--noautocomplete`). Autocomplete is disabled because
it uses `Module.constants` which doesn't reflect box-scoped constants.

### Plan

**Phase 1: Better constant discovery**
- Implement a `constants` method on the root box that returns all accessible
  constants (own + dependency constants)
- Expose this via a helper: `Boxwerk.available_constants`

**Phase 2: IRB integration**
- Create a custom IRB completion proc that queries Boxwerk's constant index
  instead of using `Module.constants`
- Register it via `IRB::InputCompletor` or the newer `IRB::Completion` API
- This would allow re-enabling autocomplete with box-aware completions

**Phase 3: Per-package console**
- `boxwerk console --package packs/billing` — drop into a specific package's box
- Shows only that package's constants and its declared dependencies
- Useful for testing package isolation interactively
- Default (no args) opens the root package box as it does today
- Short form: `boxwerk console -p packs/billing`

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

Currently, gems in the root `gems.rb` are loaded into the root box via
Bundler and accessible globally. Per-package gems are loaded into individual
boxes via `$LOAD_PATH` manipulation. There are several ways to improve this:

### Approach 1: Root Box Inheritance (Current)

Gems loaded in the root box are available in all boxes because `Ruby::Box.new`
creates a copy of the root box. The `boxwerk` executable runs `Bundler.setup`
and `Bundler.require` inside the root box before creating any child boxes.
This means:

- Gems required before box creation are available everywhere
- The root `gems.rb` acts as a "global" gem set
- Per-package `gems.rb` provides additional isolated gems

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

When a global gem (root `gems.rb`) and a package gem (`packs/x/gems.rb`)
specify the same gem at different versions, the package's `$LOAD_PATH`
entries take precedence because they're prepended. However, this can cause
subtle issues if the global version was already required.

**Planned resolution:**
- `boxwerk install` should detect conflicts between global and package gems
- If the same gem appears in both root and a package at different versions,
  emit a warning or error
- Explicitly prevent packages from overriding a global gem — if you need a
  different version, remove it from the global gems.rb
- Consider a `--strict` flag that errors on any overlap

### Package Gem Transitive Dependencies

Per-package gems should not be transitively accessible. If `packs/billing`
depends on `stripe` via its `gems.rb`, packages that depend on `packs/billing`
should not automatically get access to `stripe`.

**Current behaviour:** `$LOAD_PATH` manipulation means any package that
includes `packs/billing` as a dependency could potentially `require 'stripe'`
because the load paths are inherited via the box.

**Planned fix:**
- Only add per-package gem load paths to that package's box, not to boxes
  that depend on it
- If a dependent package also needs `stripe`, it should declare it in its
  own `gems.rb`

### Considerations

- **Native extensions:** Work per-box but may have global state (C-level
  globals) that leaks across boxes. This needs investigation.
- **Bundler integration:** Currently we parse lockfiles with
  `Bundler::LockfileParser` at boot (no subprocess). For a shared gem approach,
  we'd need to resolve a combined lockfile or use the root lockfile.

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## Per-Package Testing

Currently, integration tests run in the root box via `boxwerk exec rake test`.
Each package could additionally have its own test suite running in its own box:

```bash
boxwerk test packs/billing     # Run billing tests in isolated box
boxwerk test --all             # Run all package tests
```

### Current Approach

Tests in `test/` run in the root box, verifying boundary enforcement:
- Direct dependency constants are accessible
- Transitive dependencies raise `NameError`
- Private constants raise `NameError`

### Future: Per-Pack Box Tests

Each pack could have a `test/` directory with tests that run in that pack's
box. This would verify that a pack works correctly with only its declared
dependencies. The test runner would:
1. Discover test files per pack (`packs/*/test/**/*_test.rb`)
2. Run each pack's tests inside that pack's box
3. Minitest (a global gem) would be available in all boxes via root box inheritance

## IDE Support

- Language servers could be aware of package boundaries
- Autocomplete could filter to only accessible constants
- Privacy violations could be highlighted in real-time
