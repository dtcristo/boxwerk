<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk enforces package boundaries at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) isolation. Each package gets its own `Ruby::Box` — constants are resolved lazily on first access and cached. Only direct dependencies are accessible; transitive dependencies are blocked.

Boxwerk reads standard [Packwerk](https://github.com/Shopify/packwerk) `package.yml` files. Packwerk itself is optional — Boxwerk works standalone.

## Goals

- **Enforce boundaries at runtime.** `Ruby::Box` turns architectural guidelines into runtime guarantees. Undeclared dependencies and privacy violations raise `NameError`.
- **Enable gradual modularization.** Add `package.yml` files around existing code and declare dependencies incrementally.
- **Feel Ruby-native.** Integrates with Bundler, `gems.rb`/`Gemfile`, and standard Ruby tools. `boxwerk exec rake test` feels like any other Ruby command.
- **Work standalone.** Packwerk is optional for static analysis at CI time, but not required at runtime.

## Ruby::Box

[`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) (Ruby 4.0+) provides in-process isolation of classes, modules, and constants. Each box has its own top-level `Object`, isolated `$LOAD_PATH` and `$LOADED_FEATURES`, and independent monkey patches. Boxwerk creates one box per package and wires cross-package constant resolution through `const_missing`.

Set `RUBY_BOX=1` before starting Ruby. See the [official documentation](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) for details. See [ARCHITECTURE.md](ARCHITECTURE.md) for how Boxwerk uses Ruby::Box internally.

## Quick Start

Add `boxwerk` to your `gems.rb`:

```ruby
source 'https://rubygems.org'
gem 'boxwerk'
```

Create packages with `package.yml` files:

```
my_app/
├── package.yml           # root package
├── app.rb
├── gems.rb
└── packs/
    ├── foo/
    │   ├── package.yml
    │   └── lib/foo.rb
    └── bar/
        ├── package.yml
        └── lib/bar.rb
```

```yaml
# package.yml (root)
enforce_dependencies: true
dependencies:
  - packs/foo
  - packs/bar
```

Install and run:

```bash
bundle install
bundle binstubs boxwerk
RUBY_BOX=1 bin/boxwerk run app.rb
```

See [USAGE.md](USAGE.md) for full documentation including CLI reference, package configuration, per-package gems, privacy enforcement, and testing.

## CLI

```
boxwerk run <script.rb>             Run a Ruby script in a package box
boxwerk exec <command> [args...]    Execute a command in the boxed environment
boxwerk console                     Interactive console in a package box
boxwerk info                        Show package structure and dependencies
boxwerk install                     Install gems for all packages
```

Options: `-p <package>`, `--all`, `-r` (root box). See [USAGE.md](USAGE.md) for details.

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- IRB autocomplete disabled in console

See [TODO.md](TODO.md) for plans to address these.

## Examples

- [`examples/minimal/`](examples/minimal/) — Three packages, dependency enforcement, no gems
- [`examples/complex/`](examples/complex/) — Namespaced constants, privacy, per-package gems, tests
- [`examples/rails/`](examples/rails/) — Rails with ActiveRecord, foundation package, privacy

## Development

```bash
bundle install                        # Install dependencies
RUBY_BOX=1 bundle exec rake           # Run all tests (unit, e2e, examples)
bundle exec rake format               # Format code
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
