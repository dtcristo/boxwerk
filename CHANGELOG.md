# Changelog

## [Unreleased]

### Breaking Changes
- **Packwerk no longer required**: Boxwerk now works standalone. Package discovery uses direct YAML parsing instead of `Packwerk::PackageSet`. Packwerk is optional (for static analysis at CI time).
- **Packs convention**: Example uses `packs/` directory instead of `packages/`. Both are supported — Boxwerk finds `package.yml` files anywhere via glob.

### Added
- **`Boxwerk::Package`**: Simple data class replacing `Packwerk::Package`. Loads from `package.yml` files directly.
- **`boxwerk install`**: CLI command that runs `bundle install` in all packs with a Gemfile.
- **Lazy constant loading**: No eager code loading at boot — files loaded on first access via `autoload` and `const_missing`
- **CLI `info` command**: Shows package structure, dependencies, layers, and enforcement flags
- **CLI `--version`/`-v` flag**: Prints version and exits
- **Zeitwerk integration**: Uses Zeitwerk inflection for file→constant naming conventions
- **Visibility enforcement**: `enforce_visibility` + `visible_to` restricts which packages can access a package
- **Folder privacy enforcement**: `enforce_folder_privacy` restricts access to sibling/parent packages
- **Layer enforcement**: `enforce_layers` + `layer` with `layers` defined in `packwerk.yml` prevents architectural violations
- **Per-package gem isolation**: Each package can have its own `Gemfile`/`gems.rb` with isolated gem versions via `$LOAD_PATH` per box
- **Privacy enforcement**: Compatible with [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions) privacy config
- Comprehensive test suite: 95 integration tests + 34 end-to-end tests
- **FUTURE_IMPROVEMENTS.md**: Documents global gems, Rails integration, and other planned enhancements

### Changed
- **Standalone package discovery**: `PackageResolver` reads `packwerk.yml` for `package_paths`/`exclude` config, then globs for `package.yml` files. No Packwerk gem required.
- **Lazy loading**: Replaced eager code loading with `build_file_index` + `setup_autoloader`
- Upgraded to Ruby 4.0.1 (pinned via `.mise.toml`)
- Added `zeitwerk` as explicit gem dependency

### Removed
- `packwerk` gem dependency (now optional)

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
