# Future Improvements

This document outlines planned improvements and design considerations for Boxwerk.

## Global Gems

Currently, gems in the root `Gemfile` are loaded into the root box via Bundler and accessible globally. Per-package gems are loaded into individual boxes via `$LOAD_PATH` manipulation. There are several ways to improve this:

### Approach 1: Root Box Inheritance (Current)

Gems loaded in the root box are available in all boxes because `Ruby::Box.new` creates a copy of the ROOT box (the bootstrap box), not the main box. This means:

- Gems required before box creation are available everywhere
- The root `Gemfile` acts as a "global" gem set
- Per-package `Gemfile` provides additional isolated gems

**Limitation:** Gems required after box creation are NOT shared. The order of operations matters.

### Approach 2: Shared Gem Box

Create a dedicated "gems" box at the bottom of the dependency tree that all packages depend on:

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

**Implementation:**
1. Create a virtual "gems" package (no package.yml needed)
2. Boot it first, require all shared gems into it
3. Wire it as a dependency of every package that needs shared gems
4. Packages that want isolation simply don't depend on the gems package

### Approach 3: Gem Layers

Combine both approaches — have multiple gem "layers":

```yaml
# packwerk.yml
gem_layers:
  - name: core
    gemfile: Gemfile.core   # ActiveSupport, JSON, etc.
  - name: web
    gemfile: Gemfile.web    # Rails, Rack, etc.
```

Packages declare which gem layers they need. This would require custom config, which conflicts with the current "no custom YAML" constraint.

### Considerations

- **Gem conflicts:** When two packages depend on different versions of the same gem, `$LOAD_PATH` isolation handles this naturally. But if a shared gem layer includes one version, packages can't override it.
- **Native extensions:** Work per-box but may have global state (C-level globals) that leaks across boxes. This needs investigation.
- **Bundler integration:** Currently we parse `Gemfile.lock` with `Bundler::LockfileParser` at boot (no subprocess). For a shared gem approach, we'd need to resolve a combined lockfile or use the root lockfile.

## Rails Integration

Rails is the primary target for Packwerk, so Boxwerk should eventually work with Rails applications.

### Challenges

1. **Railties and Engine loading:** Rails expects gems to be globally available and uses Railties for initialization. Each gem with a Railtie registers hooks that run during boot. These hooks assume a single global constant namespace.

2. **ActiveSupport autoloading:** Rails uses Zeitwerk via ActiveSupport for autoloading. Boxwerk's box isolation conflicts with this because Zeitwerk's `const_missing` hooks are registered on `Module` in the main context, not inside boxes.

3. **ActiveRecord models:** Models share a database connection and schema. Even if isolated in boxes, they need to reference each other for associations (`belongs_to`, `has_many`). This requires cross-box constant resolution.

4. **Initializers and middleware:** Rails initializers and middleware run in a specific order and assume global state. Boxing them would break the initialization chain.

### Proposed Approach

A Rails integration would likely work as follows:

1. **Rails itself as a global gem:** Rails and its dependencies (ActiveSupport, ActiveRecord, ActionPack, etc.) would be in the root/shared gem layer, available to all boxes.

2. **Application code in packages:** Controllers, models, services, jobs, etc. would live in packages with their own boxes.

3. **Packwerk compatibility:** Since Rails apps already use Packwerk for static analysis, Boxwerk would read the same `package.yml` files and enforce boundaries at runtime.

4. **Selective isolation:** Not everything needs to be in a box. Rails core components (Application, routes, middleware) would stay in the main context. Package code gets isolated.

### Minimal Rails Example (Planned)

```
rails_app/
├── Gemfile                    # Rails + shared gems
├── packwerk.yml               # Layer definitions
├── package.yml                # Root package
├── config/                    # Rails config (not boxed)
│   ├── application.rb
│   └── routes.rb
├── app/
│   └── controllers/
│       └── application_controller.rb
└── packs/
    ├── billing/
    │   ├── package.yml
    │   ├── app/
    │   │   ├── controllers/
    │   │   ├── models/
    │   │   └── services/
    │   └── lib/
    └── inventory/
        ├── package.yml
        ├── app/
        │   ├── controllers/
        │   ├── models/
        │   └── services/
        └── lib/
```

## Zeitwerk Autoloading Inside Boxes

Currently, Zeitwerk's autoloading does NOT work inside `Ruby::Box` because:

1. Zeitwerk registers `const_missing` hooks on `Module` in the main context
2. Inside a box, `Module` references the box's copy, not the main one
3. The hooks never fire for constants referenced inside boxes

If Ruby::Box evolves to support shared `Module` hooks or per-box Zeitwerk loaders, this would enable:
- Full Zeitwerk autoloading inside each package's box
- No need for our custom `autoload` registration or file index scanning
- Seamless integration with Rails' autoloading

## Constant Reloading

Currently, constants loaded into a box are permanent — there's no way to "unload" them. This makes development workflows (edit → reload → test) impossible without restarting the process.

Potential approaches:
- Recreate boxes on file change (expensive but correct)
- Track loaded constants and remove them from the box before reloading
- Use Ruby::Box's future API for constant removal (if added)

## Development Workflow

### Packs CLI Integration

[Packs](https://github.com/rubyatscale/packs) provides CLI tools for managing package structure. Potential integration:

```bash
packs create packs/billing          # Creates package structure
boxwerk info                        # Shows runtime enforcement view
packwerk check                      # Static analysis (optional)
RUBY_BOX=1 boxwerk run app.rb       # Runtime enforcement
```

### IDE Support

- Language servers could be aware of package boundaries
- Autocomplete could filter to only accessible constants
- Privacy violations could be highlighted in real-time

## Per-Package Testing

Each package could have its own test suite that runs in its own box:

```bash
boxwerk test packs/billing     # Run billing tests in isolated box
boxwerk test --all             # Run all package tests
```

This would verify that packages work correctly in isolation, not just when all code is loaded together.
