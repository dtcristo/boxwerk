# Changelog

## [Unreleased] — v0.3.0

Complete architecture rewrite. Boxwerk now enforces package boundaries at
runtime using `Ruby::Box` isolation instead of static analysis.

### Breaking Changes

- **Runtime isolation via Ruby::Box.** Each package runs in its own
  `Ruby::Box`. Constants are resolved lazily via `const_missing` and cached.
  Only direct dependencies are accessible; transitive dependencies raise
  `NameError`.
- **No namespace wrapping.** Dependency constants are accessed directly
  (`Invoice`, not `Finance::Invoice`).
- **Removed checkers.** Only `enforce_privacy` remains. Removed
  `enforce_visibility`, `enforce_folder_privacy`, and `enforce_layers`.
- **Removed `packwerk.yml`.** Package discovery uses `package.yml` files only.
- **Default `public_path` changed** to `public/`.
- **Removed Zeitwerk dependency.** Uses `autoload` directly inside boxes.

### Added

- **CLI commands:** `exec`, `run`, `console`, `install`, `info`.
- **Package flags:** `--package`/`-p`, `--all`, `--root-box`/`-r`.
- **Per-package gem isolation.** Packages can have their own `Gemfile` with
  different gem versions.
- **Per-package testing.** `boxwerk exec --all rake test` runs each package's
  tests in isolated subprocesses.
- **Bundler re-exec.** When invoked via `bundle exec` or binstub, Boxwerk
  re-execs into a clean Ruby process to prevent double gem loading.
- **Privacy enforcement.** `enforce_privacy`, `public_path`,
  `private_constants`, `pack_public: true` sigil.
- `ARCHITECTURE.md`, `TODO.md`, `AGENTS.md`.
- `examples/simple/` with per-package gems, tests, and privacy demos.
- `examples/rails/README.md` integration plan.

### Removed

- `VisibilityChecker`, `FolderPrivacyChecker`, `LayerChecker`.
- `packwerk.yml` support.
- Zeitwerk runtime dependency.
- Namespace wrapping (`PackageResolver.namespace_for`).

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
