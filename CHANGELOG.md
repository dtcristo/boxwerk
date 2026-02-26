# Changelog

## [Unreleased]

### Breaking Changes
- **No namespace wrapping**: Constants from dependencies are now accessible directly (e.g. `Invoice` instead of `Finance::Invoice`). A `const_missing` handler searches all direct dependencies.
- **Default public_path changed**: Default is now `public/` instead of `app/public/`.
- **Removed features**: Visibility checker (`enforce_visibility`), folder-privacy checker (`enforce_folder_privacy`), and layer checker (`enforce_layers`) have been removed. Only the privacy checker remains.
- **Removed packwerk.yml**: No longer read or required. Package discovery uses `package.yml` files only.
- **Executable changed**: No longer checks `ENV['RUBY_BOX']`. Checks `Ruby::Box.enabled?` instead.

### Changed
- Renamed `Gemfile` → `gems.rb` throughout (root, example, packs)
- Moved example to `examples/simple/`
- `PackageResolver` no longer reads `packwerk.yml` or derives namespaces
- `ConstantResolver` installs a dependency resolver instead of namespace proxies
- Updated gemspec description (removed packwerk-extensions reference)

### Added
- `examples/rails/README.md`: Comprehensive Rails integration plan
- Expanded `FUTURE_IMPROVEMENTS.md` with detailed plans for Zeitwerk autoloading, IRB console improvements, and constant reloading

### Removed
- `VisibilityChecker`, `FolderPrivacyChecker`, `LayerChecker` modules
- `LayerViolationError` exception class
- `PackageResolver.namespace_for` method
- `packwerk.yml` support
- Complementary Tools section from README

## [v1.0.0] - 2026-02-26

### Breaking Changes
- **Full rewrite**: Boxwerk is now a runtime package isolation tool using Ruby::Box
- **Packwerk format**: Uses Packwerk's `package.yml` format for configuration
- **No custom config**: Removed `exports` and `imports` from `package.yml`; uses `dependencies` and `enforce_dependencies` instead
- **Namespace-based access**: Dependencies accessed via derived namespace (e.g., `packs/finance` → `Finance::Invoice`)

### Added
- `PackageResolver`: Discovers packages via `package.yml` globbing, builds dependency map, topological sort
- `BoxManager`: Creates `Ruby::Box` per package, loads code, wires namespace proxy modules
- `ConstantResolver`: Creates proxy modules with `const_missing` for lazy constant resolution and caching
- Transitive dependency prevention: only direct dependencies are searchable

### Removed
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
