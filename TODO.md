# TODO

Planned improvements for Boxwerk, ordered by priority.

## Summary

| # | Item | Priority | Status |
|---|------|----------|--------|
| 1 | `Boxwerk.package` as box constant | High | ✅ Done |
| 2 | Immediate autoload in boot scripts (`autoloader.setup`) | High | ✅ Done |
| 3 | `eager_load_global` / `eager_load_packages` config | High | ✅ Done |
| 4 | Global context loads all package constants | High | ✅ Done |
| 5 | Selective package booting | High | ✅ Done |
| 6 | Work without gems entirely | High | ✅ Done |
| 7 | `boxwerk-rails` gem | Medium | Future |
| 8 | Fix `rails console` crash | Medium | Not started |
| 9 | GitHub Action CI fix | Medium | ✅ Done |
| 10 | CLI config without `boxwerk.yml` | Medium | ✅ Done |
| 11 | Exec command shell fallback | Medium | ✅ Done |
| 12 | `-a` CLI option (alias of `--all`) | Medium | ✅ Done |
| 13 | Fix double NameError in console | Medium | ✅ Done |
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

## 1. `Boxwerk.package` as Box Constant

**Priority: High**

`Boxwerk.package` currently uses a thread-local (`Thread.current[:boxwerk_package_context]`) set only during `boot.rb` execution and cleared afterwards — it returns `nil` in regular package code. Instead, `Boxwerk.package` should return the `BOXWERK_PACKAGE` constant from the calling box, making it available at any point inside package code.

### Implementation Plan

1. **Remove thread-local** — Delete the `Thread.current[:boxwerk_package_context]` getter/setter from `lib/boxwerk.rb`.
2. **Resolve from box constant** — `Boxwerk.package` should return the `BOXWERK_PACKAGE` constant set in the current box. Since `Boxwerk` is defined in the root box, it needs to detect the calling box context. Options:
   - Use `Ruby::Box.current` (if available in Ruby 4.0 API) to get the box, then `box.const_get(:BOXWERK_PACKAGE)`.
   - Alternatively, keep `BOXWERK_PACKAGE` as the primary API and have `Boxwerk.package` be a convenience that reads it.
3. **Ensure BOXWERK_PACKAGE is set early** — It's already set in `run_package_boot` in `box_manager.rb`. Move the `const_set` to happen before `boot.rb` runs (it already does — line 163). Ensure it's also set for packages without a `boot.rb`.
4. **Update boot.rb flow** — Remove the `Boxwerk.package = context` / `Boxwerk.package = nil` lines in `box_manager.rb`.
5. **Update USAGE.md** — Remove mention of "thread-local, `nil` outside boot".
6. **Update tests** — Ensure `BOXWERK_PACKAGE` is accessible in package code, not just boot scripts.

---

## 2. Immediate Autoload in Boot Scripts (`autoloader.setup`)

**Priority: High**

Currently, when `push_dir` is called in a package's `boot.rb`, the new autoload dirs are not registered until *after* `boot.rb` completes (in `apply_boot_config`). This means constants from newly added autoload dirs can't be used later in the same `boot.rb`. Additionally, there is no need for a separate `boot/` directory concept in packages since the boot script already has access to the package's default autoloaded constants (`lib/`, `public/`).

The `global/` directory at the project root is unaffected — it remains as-is.

### Implementation Plan

1. **Add `Boxwerk.package.autoloader.setup` method** — When called in `boot.rb`, immediately scan and register autoload entries for any dirs added via `push_dir` or `collapse` so far. This requires the autoloader to hold a reference to the box and use `ZeitwerkScanner.scan` + `ZeitwerkScanner.register_autoloads` on the fly.
2. **Pass box reference to Autoloader** — `PackageContext::Autoloader.new(pkg_dir, box: box)` so `setup` can register autoloads in the correct box.
3. **Track registered dirs** — Avoid double-registering dirs already scanned by `setup` when `apply_boot_config` runs after boot.
4. **Update docs** — Document `autoloader.setup` in USAGE.md per-package boot scripts section. Note that `setup` is optional — dirs are always registered after boot, but `setup` makes them available immediately.
5. **Test** — Add test where boot.rb calls `push_dir`, then `setup`, then references a constant from the new dir.

---

## 3. `eager_load_global` / `eager_load_packages` Config

**Priority: High**

Two new `boxwerk.yml` options to control eager loading during boot:

- **`eager_load_global`** (default: `true`) — When `true`, calls `Zeitwerk::Loader.eager_load_all` after `global/boot.rb` has run and eager-loads all files in `global/`. When `false`, skips both. The `global/boot.rb` script itself always runs regardless. When `false` we're still able to lazy-load via autoload code from within `global/` from package boxes (although due to how Ruby::Box works, won't be visible as loaded in other packages).
- **`eager_load_packages`** (default: `false`) — When `true`, eager-loads all constants in each package box after boot. When `false` (default), constants are lazy-loaded via autoload.

These options do not affect `boot.rb` / `global/boot.rb` execution (always run) or automatic gem requiring from Gemfiles (always happens).

### Investigation: Does `Zeitwerk::Loader.eager_load_all` Actually Do Anything?

The call exists in `setup.rb#eager_load_zeitwerk`. It resolves pending Zeitwerk autoloads in the root box so child boxes inherit fully resolved constants. Gems like Rails use Zeitwerk internally — without eager loading, child boxes may inherit unresolvable autoload entries. This call IS necessary for gems with internal Zeitwerk autoloading.

### Implementation Plan

1. **Parse new config** — Read `eager_load_global` and `eager_load_packages` from `boxwerk.yml` in `PackageResolver#load_boxwerk_config`. Pass through to `Setup.run`.
2. **Guard `eager_load_zeitwerk`** — In `Setup.run`, only call `eager_load_zeitwerk` when `eager_load_global` is `true` (default).
3. **Guard `global/` file loading** — In `run_global_boot`, only require non-boot global files when `eager_load_global` is `true`. `global/boot.rb` always runs.
4. **Add package eager loading** — In `BoxManager.boot`, after all autoloads are registered and deps wired, optionally eager-load all constants in the box when `eager_load_packages` is `true`.
5. **Update USAGE.md** — Add config options to the `boxwerk.yml` section.
6. **Tests** — Unit tests for both options in `setup_test.rb`.

---

## 4. Global Context Loads All Package Constants

**Priority: High**

When using `run`, `console`, and `exec` in global context (`-g`), the global context should be able to resolve constants from ALL packages. This makes debugging easier. Global run/console/exec should run after all packages have booted.

### Current Behaviour

The `--global` flag runs directly in `Ruby::Box.root` with no package constant resolution — only global gems are available.

### Implementation Plan

1. **Install composite resolver on root box** — After all packages are booted, install a `const_missing` on `Ruby::Box.root` that searches all packages (similar to an implicit root package with `enforce_dependencies: false`).
2. **Ensure all packages boot first** — Global mode should still call `perform_setup` (it does already) which boots all packages.
3. **Reuse existing resolver logic** — Use `ConstantResolver.build_resolver` with all packages as deps, no privacy enforcement.
4. **Tests** — Verify global context can access constants from any package.

---

## 5. Selective Package Booting

**Priority: High**

When using `run`, `exec`, and `console` for a specific package (`-p packs/foo`), only boot the necessary packages: global, then the target package and all its transitive dependencies. Other packages should not be booted.

### Current Behaviour

`perform_setup` calls `Setup.run` which boots ALL packages via `boot_all`.

### Implementation Plan

1. **Add `boot_package(package, resolver)` to BoxManager** — Recursively boot only the target package and its transitive deps (via DFS on `package.dependencies`).
2. **Add `packages` parameter to `Setup.run`** — Optional list of packages to boot. Default `nil` boots all.
3. **Determine target in CLI** — In `exec_command`, `run_command`, `console_command`, determine target package from flags and pass to setup.
4. **Global mode still boots all** — When `-g` is used, boot all packages (for the global resolver from item 4).
5. **`--all` still boots all** — Each subprocess boots its own target package independently.
6. **Tests** — Verify only target + deps are booted, not unrelated packages.

---

## 6. Work Without Gems Entirely

**Priority: High**

Boxwerk should work without any root/global Gemfile. In this mode:
- Use a system-installed `boxwerk` (not bundled)
- No gems loaded into global context (except Boxwerk itself)
- Per-package gems still supported (optional) but require Bundler on the system
- `boxwerk install` should not crash without a root Gemfile

### Implementation Plan

1. **Guard Bundler calls** — In `exe/boxwerk`, the root box eval already checks `gemfile` existence. Ensure it doesn't crash when nil. Same for `install_command`.
2. **Minimal example** — Remove `gems.rb` and `Rakefile` from `examples/minimal/`. Add a simple shell script (e.g. `run.sh`) or `Makefile` for CI execution instead of rake.
3. **Update minimal README** — Remove Bundler setup steps. Show direct `boxwerk run main.rb` usage.
4. **Update main README Quick Start** — Show gemless workflow as the simplest path. Move Bundler setup to USAGE.md.
5. **Update USAGE.md** — Add a section on using Boxwerk with Bundler (creating binstub, etc.) and without Bundler (system install).
6. **`boxwerk install` safety** — Skip root package in `install_command` when no Gemfile exists. Already partially handles this.
7. **Tests** — E2E test with minimal example without Gemfile.

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

## 9. GitHub Action CI Fix

**Priority: Medium**

Faker gem is missing in CI causing specs to fail. The step that installs package gems may be missing `bundler-cache: true`. Also, the install task should not need a regular `bundle install` first — it should rely solely on `bin/boxwerk install`.

### Implementation Plan

1. **Fix install step** — In `.github/workflows/main.yml`, the per-example install loop does `bundle install` then `bin/boxwerk install`. The first `bundle install` is needed for the example's root gems (including boxwerk itself). Keep it but ensure caching works.
2. **Check bundler-cache** — The main setup-ruby step has `bundler-cache: true`. Per-example installs are manual. Consider caching example gem directories.
3. **Verify Faker** — Check if `examples/complex/packs/kitchen/gems.rb` (which requires Faker) gets its lockfile gems installed during `bin/boxwerk install`.
4. **Test locally** — Run the full CI flow to reproduce the issue.

---

## 10. CLI Config Without `boxwerk.yml`

**Priority: Medium**

Allow providing `boxwerk.yml` configuration via CLI options instead of a config file. This enables quick configuration without creating a file.

### Implementation Plan

1. **Add `--package-paths` option** — Parse `--package-paths "packs/*"` in the CLI and pass to `Setup.run` / `PackageResolver`.
2. **CLI options override file** — If both CLI option and `boxwerk.yml` exist, CLI takes precedence.
3. **Extend to new config options** — Also support `--global-eager-load` / `--package-eager-load` flags.
4. **Update USAGE.md** — Document CLI config options in the options table.

---

## 11. Exec Command Shell Fallback

**Priority: Medium**

When `boxwerk exec` can't find a binstub or gem bin for the given command, it should fall back to treating the remaining args as a shell command that runs in the package directory as cwd.

### Implementation Plan

1. **Modify `run_command_in_box`** — In `cli.rb`, after checking project bin and gem bin, fall back to `system(*command_args, chdir: pkg_dir)` running in the package directory.
2. **Use `Kernel.exec` or `system`** — Since this is a shell command, use `system` with the package dir as cwd. The command runs outside box context (native shell).
3. **Update docs** — Document the fallback behaviour in USAGE.md exec section.

---

## 12. `-a` CLI Option (Alias of `--all`)

**Priority: Medium**

Add `-a` as a short alias for `--all` in the CLI.

### Implementation Plan

1. **Update `parse_package_flag`** — Add `'-a'` to the case match alongside `'--all'`.
2. **Update CLI help text** — Show `-a` in the options table.
3. **Update USAGE.md** — Add `-a` to the options table.

---

## 13. Fix Double NameError in Console

**Priority: Medium**

When a `NameError` occurs in `boxwerk console`, the error and stack trace are printed twice. Should be printed once.

### Implementation Plan

1. **Reproduce** — Start a console and reference a non-existent constant. Observe double output.
2. **Investigate** — Likely caused by the composite resolver on `Ruby::Box.root` rethrowing the error, plus IRB's own error handler catching and displaying it. Or `const_missing` being called twice (once by Object, once by the composite resolver).
3. **Fix** — Ensure the resolver raises `NameError` exactly once. Check if the composite resolver in `install_resolver_on_ruby_root` re-raises after the dep resolver already raised. May need to catch and re-raise cleanly without double display.
4. **Test** — Console test verifying single error output.

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

---

## Done

Items completed and removed from active tracking:

- ✅ **Zeitwerk integration** — File scanning, inflection, `autoload_dirs`,
  `collapse_dirs`, eager loading. Remaining: `ignore_dirs` consumption,
  reloading (see #14).
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
- ✅ **USAGE.md global/boot.rb description** — Updated to describe eager
  loading constants (e.g. Rails internals), not "booting Rails". Root
  `boot.rb` is for booting Rails in the root package.
- ✅ **README description** — Updated tagline to "Ruby package system with
  Box-powered constant isolation". Packwerk standalone note clarified.
- ✅ **README TODO mention** — Updated to mention other planned features.
- ✅ **Rails console docs** — Updated `examples/rails/README.md` to recommend
  `boxwerk console` instead of `boxwerk exec rails console`.
- ✅ **USAGE.md boot.rb docs** — Clarified per-package gems are available in
  boot scripts. Added Bundler mention to USAGE.md reference in README.
