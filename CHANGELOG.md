# Changelog

## [Unreleased]

### Added
- **Zeitwerk integration**: Uses Zeitwerk inflection for file→constant naming conventions
- **Visibility enforcement**: `enforce_visibility` + `visible_to` restricts which packages can access a package
- **Folder privacy enforcement**: `enforce_folder_privacy` restricts access to sibling/parent packages
- **Layer enforcement**: `enforce_layers` + `layer` with `layers` defined in `packwerk.yml` prevents architectural violations
- **Per-package gem isolation**: Each package can have its own `Gemfile`/`gems.rb` with isolated gem versions via `$LOAD_PATH` per box
- **GemResolver**: Parses `Gemfile.lock` with `Bundler::LockfileParser`, resolves gem paths via `Gem::Specification`
- **VisibilityChecker** module: reads `enforce_visibility` and `visible_to` from package.yml
- **FolderPrivacyChecker** module: reads `enforce_folder_privacy`, enforces sibling/parent access rules
- **LayerChecker** module: reads `enforce_layers`, `layer` from package.yml and `layers` from `packwerk.yml`
- `LayerViolationError` raised at boot time for layer constraint violations
- **Privacy enforcement**: Compatible with [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) privacy config
  - `enforce_privacy: true` in `package.yml` restricts constant access to the public API
  - `public_path` (default: `app/public/`) defines the public API directory
  - `pack_public: true` sigil makes individual files public
  - `private_constants` explicitly blocks specific constants
- `PrivacyChecker` module: reads packwerk-extensions config and enforces privacy at runtime
- Comprehensive test suite: 81 tests, 138 assertions

### Changed
- Upgraded to Ruby 4.0.1 (pinned via `.mise.toml`)
- Added `zeitwerk` as explicit gem dependency
- `PackageResolver` and `PrivacyChecker` now use `Zeitwerk::Inflector#camelize` instead of manual inflection

## [v1.0.0] - 2026-02-26

### Breaking Changes
- **Full rewrite**: Boxwerk is now a runtime enforcement companion to Packwerk
- **Packwerk dependency**: Boxwerk depends on and reads Packwerk's `package.yml` format
- **No custom config**: Removed `exports` and `imports` from `package.yml`; uses Packwerk's `dependencies` and `enforce_dependencies` instead
- **Namespace-based access**: Dependencies accessed via derived namespace (e.g., `packages/finance` → `Finance::Invoice`)
- **No selective/renamed imports**: All constants in a dependency package are accessible via the namespace

### Added
- `PackageResolver`: Discovers packages via Packwerk's `PackageSet`, builds dependency map, topological sort
- `BoxManager`: Creates `Ruby::Box` per package, loads code, wires namespace proxy modules
- `ConstantResolver`: Creates proxy modules with `const_missing` for lazy constant resolution and caching
- Transitive dependency prevention: only direct dependencies are searchable

### Removed
- `Graph` class (replaced by `PackageResolver` using Packwerk)
- `Package` class (replaced by Packwerk's `Package`)
- `Loader` class (replaced by `BoxManager`)
- `Registry` class (box tracking moved to `BoxManager`)
- Custom `exports`/`imports` YAML configuration
- Import strategies (aliased, selective, renamed)

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

[Unreleased]: https://github.com/dtcristo/boxwerk/compare/v1.0.0...HEAD
[v1.0.0]: https://github.com/dtcristo/boxwerk/releases/tag/v1.0.0
[v0.2.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.2.0
[v0.1.0]: https://github.com/dtcristo/boxwerk/releases/tag/v0.1.0
