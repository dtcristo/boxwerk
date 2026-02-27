# Changelog

## [Unreleased] — v0.3.0

Complete rewrite: Boxwerk is now a runtime package isolation tool using
Ruby::Box with lazy constant loading, per-package gem isolation, and a
CLI designed to feel Ruby-native.

### Breaking Changes
- **No namespace wrapping**: Constants from dependencies are accessible
  directly (e.g. `Invoice` instead of `Finance::Invoice`). A `const_missing`
  handler on `Object` within each box searches direct dependencies.
- **Default public_path changed**: Default is now `public/` instead of
  `app/public/`.
- **Removed checkers**: Visibility checker (`enforce_visibility`),
  folder-privacy checker (`enforce_folder_privacy`), and layer checker
  (`enforce_layers`) have been removed. Only the privacy checker remains.
- **Removed packwerk.yml**: No longer read or required. Package discovery
  uses `package.yml` files only.
- **Executable changed**: Checks `defined?(Ruby::Box)` and
  `Ruby::Box.enabled?` instead of `ENV['RUBY_BOX']`.
- **Install method**: Boxwerk is designed to be installed via
  `gem install boxwerk` rather than through Bundler, avoiding double gem
  loading.
- **Removed zeitwerk dependency**: File-to-constant mapping now uses an
  inline `Boxwerk.camelize` method instead of Zeitwerk's inflector.

### Added
- **`boxwerk exec` command**: Execute any Ruby command in the boxed
  environment (e.g. `boxwerk exec rake test`, `boxwerk exec rails console`).
- **`boxwerk run` command**: Run a Ruby script in the root package box.
- **`boxwerk console` command**: Interactive IRB in the root package box.
- **`boxwerk install` command**: Bundle install for all packages with a
  `Gemfile`/`gems.rb`.
- **`boxwerk info` command**: Show package structure, dependencies, and flags.
- **`--package`/`-p` flag**: Target a specific package box for `run`, `exec`,
  and `console` commands (e.g. `boxwerk exec -p packs/util rake test`).
- **`--all` flag**: Run `exec` commands across all packages sequentially,
  each in its own subprocess for clean isolation.
- **Per-package gem version isolation**: Packages can have their own
  `Gemfile`/`gems.rb` with different gem versions. Each box gets isolated
  `$LOAD_PATH` entries.
- **Per-package testing**: Each package can have its own `test/` directory
  and `Rakefile`. Run with `boxwerk exec -p packs/name rake test`.
- **Lazy constant loading**: Constants loaded on first access via `autoload`
  and `const_missing`, then cached.
- **Privacy enforcement**: `enforce_privacy`, `public_path`,
  `private_constants`, and `pack_public: true` sigil.
- **Transitive dependency blocking**: Only direct dependencies are accessible.
- **Goals section** in README inspired by Packwerk.
- **Ruby::Box section** in README summarising relevant Box behaviours.
- **Gem loading architecture** section in README explaining the root box
  inheritance model.
- `examples/simple/`: Multi-package example with faker version isolation,
  per-package unit tests, and per-package gems.
- `examples/rails/README.md`: Comprehensive Rails integration plan.
- `FUTURE_IMPROVEMENTS.md`: Plans for IRB console, constant reloading,
  global gems, gem conflicts, Bundler-inspired commands, and more.

### Changed
- Renamed `Gemfile` → `gems.rb` throughout (both formats supported).
- `PackageResolver` no longer reads `packwerk.yml` or derives namespaces.
- `ConstantResolver` installs a dependency resolver on `Object` within each
  box instead of namespace proxies.
- `GemResolver` searches all gem directories (not just current bundle) for
  per-package gem isolation.
- Example restructured from `example/` → `examples/simple/`.

### Removed
- `VisibilityChecker`, `FolderPrivacyChecker`, `LayerChecker` modules.
- `LayerViolationError` exception class.
- `PackageResolver.namespace_for` method.
- `packwerk.yml` support.
- Zeitwerk runtime dependency.
- Complementary Tools section from README.
- Custom `exports`/`imports` YAML configuration.

## [v0.2.0] - 2026-01-06

### Changed
- Simplified implementation (~370 lines removed)
- Consolidated cycle detection in Graph (removed redundant methods)
- Removed unused Loader methods
- Streamlined all module implementations
- Added class-level documentation to all modules
- Simplified example application

### Removed
- Removed `Gemfile.lock` from git (library best practice)
- Removed `sig/boxwerk.rbs`
- Excluded `example/` from gem package

### Tests
- Reduced test suite from 62 to 46 tests
- Removed redundant unit tests (275 lines)
- Maintained full integration test coverage

## [v0.1.0] - 2026-01-05

Initial release.

[Unreleased]: https://github.com/dtcristo/boxwerk/compare/v0.2.0...HEAD
[v0.2.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.2.0
[v0.1.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.1.0
