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
  double gem loading. Commands that don't need Ruby::Box (`install`, `info`,
  `help`, `version`) work without `RUBY_BOX=1`.
- Example restructured: `example/` → `examples/simple/` with per-package
  gems, unit tests, and privacy demos. `examples/rails/` added as a plan.
- Requires Ruby >= 4.0.1 (was 4.0.0).

### Added

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
- E2E test suite (57 tests) alongside unit/integration tests (69 tests).

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
