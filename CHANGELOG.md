# Changelog

## [Unreleased] — v0.3.0

Complete architecture rewrite. Each package now runs in its own `Ruby::Box`
with constants resolved lazily at runtime. Reads standard Packwerk
`package.yml` files.

### Changed

- Constants from dependencies are accessed directly (`Invoice`, not
  `Finance::Invoice`). A `const_missing` handler on `Object` within each box
  searches direct dependencies.
- Default `public_path` changed from `app/public/` to `public/`.
- Core internals replaced: `Graph`, `Loader`, `Registry` → `BoxManager`,
  `ConstantResolver`, `GemResolver`, `PackageResolver`, `PrivacyChecker`.
- `exe/boxwerk` boots into `Ruby::Box.root`, loads gems via Bundler, then
  delegates to CLI. Re-execs when launched via `bundle exec` to prevent
  double gem loading. Commands that don't need Ruby::Box (`install`,
  `help`, `version`) work without `RUBY_BOX=1`.
- `boxwerk info` boots the application (requires `RUBY_BOX=1`) to show
  runtime autoload dirs, collapse/ignore dirs, eager load status, boot
  script presence, and per-package gems. Autoload dirs show `(eager)` when
  relevant eager load option is enabled. Global section includes path gems
  (e.g. `boxwerk`) when present in the Gemfile.
- Example restructured: `example/` → `examples/simple/` with per-package
  gems, unit tests, and privacy demos. `examples/rails/` added as a plan.
- Requires Ruby >= 4.0.1 (was 4.0.0).

### Added

- `Boxwerk.package` public API — returns a `PackageContext` during boot.rb
  execution with `name`, `root?`, `config`, `root_path`, and `autoloader`.
- `PackageContext::Autoloader` — configuration object with `push_dir`,
  `collapse`, and `ignore` methods for boot.rb autoload configuration.
- `BOXWERK_PACKAGE` constant injected into each package box.
- CLI commands: `exec`, `run`, `console`, `install`, `info`.
- CLI flags: `-p`/`--package`, `--all`, `-r`/`--root-box`.
- Per-package gem isolation via `Gemfile`/`gems.rb` per package.
- Per-package gem auto-require: gems declared in a package's `Gemfile` are
  automatically required in the package box, matching Bundler's default
  behaviour. Supports `require: false` and `require: 'custom/path'`.
- Privacy enforcement: `enforce_privacy`, `public_path`,
  `private_constants`, `pack_public: true` sigil.
- Zeitwerk-based file scanning and inflection (`ZeitwerkScanner`).
- `irb` and `zeitwerk` gem dependencies.
- `ARCHITECTURE.md`, `TODO.md`, `AGENTS.md`.
- E2E test suite (73 tests) alongside unit/integration tests (120 tests).
- `Boxwerk.global` API — `Boxwerk.global.autoloader` in `global/boot.rb`
  registers extra root-level autoload dirs whose constants are available in
  all package boxes. Supports `push_dir`, `collapse`, `setup`, `eager_load!`.
  `push_dir` registers lazy autoloads only; `eager_load!` triggers eager require.
- `autoloader.setup` can be called in a per-package `boot.rb` to make newly
  added dirs available immediately (no longer requires explicit call — `push_dir`
  and `collapse` now auto-call `setup`).
- Package name normalization — leading `./` and trailing `/` are stripped from
  package names passed to `--package` and in `package.yml` dependencies.
- NameError hints now work when running in a child package context (e.g.
  `boxwerk exec -p packs/orders`) — hints reference the package name even
  for packages not booted in that run.
- Packages without `enforce_dependencies: true` correctly access all constants
  when run via selective boot (`-p`).
- `examples/complex` — demonstrates `eager_load_global`, `eager_load_packages`,
  `Boxwerk.global.autoloader.push_dir`, and package isolation tests.
- `boxwerk info` — restructured: Global section (root package separate from
  packages), Config section showing `boxwerk.yml` options, direct gems only
  (no transitive deps), `public_path`, `pack_public` constants, and explicit
  private constants per package. Circular dependency detection in tree.
- `PrivacyChecker.pack_public_constants` — returns constants with
  `pack_public: true` sigil separately from `public_path`-based constants.
- `eager_load_packages` now eager loads each package immediately after it
  boots (not in a second pass over all packages).
- `eager_load_global: false` now registers lazy autoloads for `global/` dir
  so constants are accessible via autoload in `boot.rb` without crashing.
- `boxwerk install` uses `Bundler.with_unbundled_env` and `--retry 3` to
  fix CI gem installation when `BUNDLE_GEMFILE` is inherited from parent.

### Removed

- Custom file-to-constant mapping (`Boxwerk.camelize`), replaced by Zeitwerk.
- Namespace wrapping.

## [v0.2.0] - 2026-01-06

### Changed
- Simplified implementation (~370 lines removed)
- Consolidated cycle detection in Graph (removed redundant methods)
- Added class-level documentation to all modules
- Simplified example application

### Removed
- Removed `Gemfile.lock` from git (library best practice)
- Removed `sig/boxwerk.rbs`

## [v0.1.0] - 2026-01-05

Initial release.

[Unreleased]: https://github.com/dtcristo/boxwerk/compare/v0.2.0...HEAD
[v0.2.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.2.0
[v0.1.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.1.0
