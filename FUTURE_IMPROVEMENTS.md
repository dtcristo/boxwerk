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
- `boxwerk console packs/billing` — drop into a specific package's box
- Shows only that package's constants and its declared dependencies
- Useful for testing package isolation interactively

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
creates a copy of the ROOT box (the bootstrap box), not the main box. This
means:

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

### Considerations

- **Gem conflicts:** When two packages depend on different versions of the
  same gem, `$LOAD_PATH` isolation handles this naturally. But if a shared gem
  layer includes one version, packages can't override it.
- **Native extensions:** Work per-box but may have global state (C-level
  globals) that leaks across boxes. This needs investigation.
- **Bundler integration:** Currently we parse lockfiles with
  `Bundler::LockfileParser` at boot (no subprocess). For a shared gem approach,
  we'd need to resolve a combined lockfile or use the root lockfile.

## Rails Integration

See [examples/rails/README.md](examples/rails/README.md) for the comprehensive
Rails integration plan.

## Per-Package Testing

Each package could have its own test suite that runs in its own box:

```bash
boxwerk test packs/billing     # Run billing tests in isolated box
boxwerk test --all             # Run all package tests
```

This would verify that packages work correctly in isolation, not just when
all code is loaded together.

## IDE Support

- Language servers could be aware of package boundaries
- Autocomplete could filter to only accessible constants
- Privacy violations could be highlighted in real-time
