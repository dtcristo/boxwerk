# Changelog

## [Unreleased]

### Changed

- `bin/setup` now installs gems for the example apps too, so the repository
  test suite works after a fresh clone.

## [v0.3.0] — 2026-03-02

Complete architecture rewrite. Each package now runs in its own `Ruby::Box`
with constants resolved lazily at runtime via `const_missing`. Reads standard
Packwerk `package.yml` files without requiring Packwerk.

### Added

- **Package isolation** — each package runs in its own `Ruby::Box`; constants
  from undeclared dependencies and private constants raise `NameError` at
  runtime.
- **Per-package gems** — packages can declare their own `gems.rb`/`Gemfile`
  with independent gem versions; auto-require mirrors Bundler's default
  behaviour (respects `require: false`, `require: 'path'`).
- **Zeitwerk autoloading** — constants discovered via Zeitwerk conventions;
  default autoload roots: `lib/` and `public/`.
- **Privacy enforcement** — `enforce_privacy`, `public_path`,
  `private_constants`, and `# pack_public: true` file sigil.
- **`Boxwerk.package`** — returns a `PackageContext` in per-package `boot.rb`
  with `name`, `root?`, `config`, `root_path`, and `autoloader`.
- **`Boxwerk.global`** — returns a `GlobalContext` from any box context.
- **Autoloader API** — `push_dir`, `collapse`, `ignore`, `setup` on both
  `PackageContext::Autoloader` and `GlobalContext::Autoloader`; shared via
  `AutoloaderMixin`. `push_dir` and `collapse` auto-call `setup` so constants
  are available immediately in boot scripts.
- **`global/boot.rb`** — runs in the root box before package boxes; shared
  constants defined here are inherited by all packages.
- **`eager_load_global`** / **`eager_load_packages`** boxwerk.yml options.
- **Package name normalization** — leading `./` and trailing `/` stripped;
  `packs/foo`, `./packs/foo`, and `packs/foo/` are equivalent.
- **CLI commands** — `exec`, `run`, `console`, `install`, `info`.
- **`boxwerk install`** — installs gems for all packages; works on a fresh
  clone without pre-installed gems.
- **`boxwerk info`** — shows config, global context, and per-package
  autoload/collapse/ignore dirs (with eager-load status), enforcements,
  dependencies, gems, and boot script presence. Boots the application
  (`RUBY_BOX=1` required).
- **NameError hints** — improved error messages like
  `(defined in 'packs/baz', not a dependency of '.')` in child package
  contexts.
- **Circular dependency detection** in `boxwerk info` tree output.
- **`collapse` / `ignore` in boot.rb** — collapses intermediate namespaces
  (e.g. `Analytics::Formatters` → `Analytics::*`); ignores dirs from
  autoloading.
- **Missing lockfile warning** — graceful message directing to
  `boxwerk install` when a Gemfile exists but no lockfile is found.
- **Monkey patch isolation** — patches defined in one package box are not
  visible in other packages or the root context.
- **`examples/complex`** and **`examples/minimal`** demonstrating all features.
- **E2E test suite** (74 tests) alongside unit tests (120 tests).
- **GitHub Pages API documentation** published from `lib/` via RDoc.

### Removed

- Custom file-to-constant mapping (`Boxwerk.camelize`), replaced by Zeitwerk.
- Namespace wrapping.

## [v0.2.0] — 2026-01-06

### Changed
- Simplified implementation (~370 lines removed)
- Consolidated cycle detection in Graph (removed redundant methods)
- Added class-level documentation to all modules
- Simplified example application

### Removed
- Removed `Gemfile.lock` from git (library best practice)
- Removed `sig/boxwerk.rbs`

## [v0.1.0] — 2026-01-05

Initial release.

[Unreleased]: https://github.com/dtcristo/boxwerk/compare/v0.3.0...HEAD
[v0.3.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.3.0
[v0.2.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.2.0
[v0.1.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.1.0
