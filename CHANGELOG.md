# Changelog

## [Unreleased]

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
