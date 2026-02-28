# TODO

Planned improvements for Boxwerk, ordered by priority.

## Summary

| # | Item | Priority | Status |
|---|------|----------|--------|
| 1 | Per-package gem auto-require | High | Done |
| 2 | `Boxwerk.package` public API | High | Done |
| 3 | Improved NameError messages | High | Done |
| 4 | Remove Rails special-casing from CLI | High | Not started |
| 5 | Rails initialization in root package | High | Investigated (blocked) |
| 6 | Move Rails e2e tests to example dir | Medium | Done |
| 7 | Monkey patch isolation example | Medium | Done |
| 8 | `boxwerk-rails` gem | Medium | Future |
| 9 | Constant reloading (dev workflow) | Medium | Not started |
| 10 | IRB console autocomplete | Medium | Not started |
| 11 | `boxwerk check` (static analysis) | Low | Not started |
| 12 | `boxwerk init` (scaffold packages) | Low | Not started |
| 13 | Sorbet support | Low | Future |
| 14 | Per-package testing improvements | Low | Not started |
| 15 | Additional CLI commands | Low | Not started |
| 16 | IDE / language server support | Low | Future |
| 17 | Bundler inside package boxes | — | Blocked (Ruby::Box) |
| 18 | RUBYOPT bootstrap | — | Blocked (Ruby::Box) |

---

## 1. Per-Package Gem Auto-Require

**Priority: High — Done**

Per-package gems declared in `Gemfile`/`gems.rb` are now auto-required after
load paths are set up, matching Bundler's default behaviour. Manual
`require 'gem_name'` is no longer needed.

Implementation: `GemfileRequireParser` extracts autorequire directives from
the Gemfile. `BoxManager#auto_require_gems` requires each gem in the package
box. Root packages are skipped (global gems are already loaded by Bundler).

See `GemResolver#parse_gemfile_requires`, `BoxManager#auto_require_gems`.

---

## 2. `Boxwerk.package` Public API

**Priority: High — Done**

`Boxwerk.package` returns a `PackageContext` during `boot.rb` with `name`,
`root?`, `config` (frozen), `root_path`, and `autoloader`. The autoloader
provides `push_dir`, `collapse`, and `ignore` for Zeitwerk configuration.

---

## 3. Improved NameError Messages

**Priority: High — Done**

NameError messages now provide Boxwerk context while matching Ruby's style:
- Privacy violations: `private constant Foo referenced from '.' — Foo is private to 'packs/a'`
- Non-dependency hints: `uninitialized constant Foo (defined in 'packs/util', not a dependency of '.')`
- Uses `NameError.new(msg, name:)` to preserve Ruby's `name` attribute

---

## 4. Remove Rails Special-Casing from CLI

**Priority: High**

`cli.rb` has `execute_rails_command` which special-cases `rails` commands.
This should be removed in favour of a general mechanism.

### Background

The special case exists because:
1. `Gem.bin_path('rails', 'rails')` triggers a Bundler warning (gem is
   `railties` not `rails`) — **already fixed** by `find_bin_path` rewrite
2. The `rails` binstub goes through `rails/cli` → `AppLoader.exec_app` →
   looks for `bin/rails` → not found → shows `rails new` help

### Plan

1. Add project-level `bin/` lookup to `run_command_in_box`: before searching
   gem binstubs, check for `./bin/<command>` in the project root. This mirrors
   how Bundler binstubs work.
2. In the rails example, create a `bin/rails` binstub that does the right
   thing when evaluated inside a box:
   ```ruby
   APP_PATH = File.expand_path("../config/application", __dir__)
   require "rails/commands"
   ```
3. Remove `execute_rails_command` and the `if command == 'rails'` branch from
   `run_command_in_box`
4. Document the `bin/` lookup order in USAGE.md
5. This approach is generic — any project can create custom binstubs

### Future

The `boxwerk-rails` gem (#8) will automate creating the `bin/rails` binstub
and other Rails-specific configuration.

---

## 5. Rails Initialization in Root Package

**Priority: High — Investigated, currently blocked**

### Goal

Initialize Rails in the root package box instead of the root box (global
context). This would allow `boxwerk exec rails server` to work without `-g`.

### Investigation Results

**Approach: Eager-load Rails in global/boot.rb, initialize in root boot.rb**

1. In `global/boot.rb`: `require "active_record/railtie"` +
   `require "action_controller/railtie"` + `Zeitwerk::Loader.eager_load_all`
2. In root `boot.rb`: `require_relative "config/application"` +
   `Application.initialize!`

**Result: Partially works.** Rails internals (`ActiveRecord::Base`,
`ActionController::Base`) are accessible in child boxes after eager loading.
However, the `Application` class defined in root `boot.rb` is only visible
in the root package box. Foundation packages (which boot BEFORE the root
package) need `ApplicationRecord < ActiveRecord::Base` and
`ApplicationController < ActionController::Base`. These work because
`ActiveRecord::Base` is inherited from the root box. But any reference to
`Application` (the Rails app instance) fails because it doesn't exist yet
during foundation package boot.

**Fundamental constraint:** Package boot order is topological — dependencies
boot before dependents. The root package boots LAST. Foundation packages boot
before the root package but need `ApplicationRecord` (which needs `ActiveRecord::Base`, not `Application` itself — this part works). The actual
`Application.initialize!` call triggers database connections, route loading,
and middleware setup. Any code that requires an initialized app must wait
until after this call.

**Rails commands specifically need `-g`** because `rails/commands` dispatches
through `Rails::Command` which calls `require APP_PATH` and then
`Rails.application.initialize!`. This all happens in the executing box's
context. When running in a child box, `Rails::Command` is not accessible
(it's loaded lazily, not via Zeitwerk). Pre-requiring `rails/command` in
global/boot.rb and eager-loading Zeitwerk makes it accessible in child boxes,
but `Rails.application` returns `nil` until `Application.initialize!` runs.

### Conclusion

**Not feasible with current architecture.** Rails must be initialized in the
global context. The root package box is created after all other packages, but
packages like foundation need `ApplicationRecord` during their boot — and
`ActiveRecord::Base` (from global gems) is what they actually inherit.

**Workaround:** Use `-g` for Rails commands. The `boxwerk-rails` gem (#8)
could alias these automatically.

**Would unblock:** A `Ruby::Box` API that allows constants defined in a child
box to be visible in sibling boxes (breaking the snapshot model), or a way to
defer package boot until after the root package initializes.

---

## 6. Move Rails E2E Tests to Example Directory

**Priority: Medium — Done**

Rails e2e tests moved to `examples/rails/test/e2e_test.rb`. Top-level Rakefile
`example_e2e` task discovers and runs per-example e2e tests.

---

## 7. Monkey Patch Isolation Example

**Priority: Medium — Done**

Complex example kitchen package demonstrates `String#to_order_ticket` monkey
patch in `boot.rb`. Integration test verifies the patch doesn't leak to other
packages. Pattern documented in USAGE.md.

---

## 8. `boxwerk-rails` Gem

**Priority: Medium — Future**

A companion gem that automatically configures Rails for Boxwerk. Would
eliminate manual setup in `global/boot.rb` and `bin/rails`.

### Scope

- Auto-configure `config.autoload_paths = []` and `config.eager_load_paths = []`
- Create a `bin/rails` binstub compatible with `boxwerk exec`
- Pre-require Rails sub-components in global boot
- Alias `boxwerk exec rails` to `boxwerk exec -g rails` automatically
- Aggregate migration paths from packages (`packs/*/db/migrate/`)
- Package-aware Rails generators

### Prerequisites

- #1 (per-package gem auto-require) — needed for clean gem loading
- #2 (`Boxwerk.package` API) — needed for package-aware generators
- Stable Boxwerk API

---

## 9. Constant Reloading

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

## 10. IRB Console Autocomplete

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

## 12. `boxwerk init`

**Priority: Low**

Scaffold a new package with `package.yml`, `lib/`, `public/`, and `test/`.

---

## 13. Sorbet Support

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

## 14. Per-Package Testing Improvements

**Priority: Low**

Tests currently run via `boxwerk exec --all rake test` with subprocess
isolation.

### Possible Improvements

- **Parallel execution** — run package tests in parallel for faster CI
- **Coverage aggregation** — merge coverage reports across packages

---

## 15. Additional CLI Commands

**Priority: Low**

- **`boxwerk outdated`** — check for outdated per-package gems
- **`boxwerk update [package]`** — update lockfiles in topological order
- **`boxwerk clean`** — remove unused lockfiles and empty directories
- **`boxwerk list`** — display packages with gem versions

---

## 16. IDE / Language Server Support

**Priority: Low — Future**

- Language servers aware of package boundaries
- Autocomplete filtered to accessible constants only
- Go-to-definition across package boundaries (respecting privacy)
- Real-time privacy violation highlighting

---

## 17. Bundler Inside Package Boxes

**Status: Blocked (Ruby::Box limitation)**

`Bundler.setup` inside a child box modifies the ROOT box's `$LOAD_PATH`
because Bundler's code is defined in the root box. Current workaround:
parse lockfiles and manipulate `$LOAD_PATH` directly.

Requires Ruby::Box changes to support Bundler running in child box context.

---

## 18. RUBYOPT Bootstrap (`-rboxwerk/setup`)

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
  reloading (see #9).
- ✅ **Rails integration** — Rails 8.1 API app, Puma, ActiveRecord,
  ActionController, foundation pattern, privacy enforcement. See
  [examples/rails/](examples/rails/).
- ✅ **Global gems** — Root `Gemfile` gems loaded in root box, inherited by
  all child boxes via snapshot. Version conflict warnings.
- ✅ **Per-package gem auto-require** (#1) — Gems auto-required matching
  Bundler behaviour. `require: false` and custom require paths supported.
- ✅ **`Boxwerk.package` API** (#2) — `PackageContext` with autoloader config.
- ✅ **Improved NameError messages** (#3) — Privacy and non-dependency hints.
- ✅ **Rails e2e tests moved** (#6) — To `examples/rails/test/e2e_test.rb`.
- ✅ **Monkey patch isolation** (#7) — Kitchen example with integration test.
