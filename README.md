<div align="center">
  <h1>
    📦 Boxwerk
  </h1>
</div>

Boxwerk is a tool for creating modular Ruby and Rails applications. It enables you to organize code into packages of Ruby files with clear boundaries and explicit dependencies. Boxwerk is heavily inspired by [Packwerk](https://github.com/Shopify/packwerk) but provides more robust enforcement at runtime using [`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html), ensuring that only public constants from direct dependencies are accessible. Violations raise `NameError`, turning architectural rules into runtime guarantees.

As your application grows, Boxwerk helps prevent accidental coupling, enforces modularity, and makes it easier to understand and modify code without breaking other parts of the system.

**[Usage Guide](USAGE_md.html)** · **[API Documentation](https://dtcristo.github.io/boxwerk/)** · **[Changelog](CHANGELOG_md.html)**

## Features

- Boxwerk reads standard Packwerk `package.yml` files, supporting both dependency and privacy enforcement. Packwerk itself is not required.
- Packages in a Boxwerk application share a set of global gems but may also define package-local ones. Multiple packages can depend on different versions of the same gem.
- `Ruby::Box` provides monkey patch isolation between packages.
- Boxwerk uses [Zeitwerk](https://github.com/fxn/zeitwerk) to automatically load constants in packages with [conventional file structure](https://github.com/fxn/zeitwerk#file-structure) although manual loading is also supported.

## Goals

- **Enforce boundaries at runtime.** `Ruby::Box` turns architectural rules into runtime guarantees. Undeclared dependencies and privacy violations raise `NameError`.
- **Enable gradual modularization.** Add `package.yml` files around existing code and declare dependencies incrementally.
- **Feel Ruby-native.** Integrates with Bundler, `gems.rb`/`Gemfile`, and standard Ruby tools. `boxwerk exec rake test` feels like any other Ruby command.

## Ruby::Box

[`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) (Ruby 4.0+) provides in-process isolation of classes, modules, and constants. Each box has its own top-level `Object`, isolated `$LOAD_PATH` and `$LOADED_FEATURES`, and independent monkey patches. Boxwerk creates one box per package and wires cross-package constant resolution through `const_missing`.

Set `RUBY_BOX=1` before starting Ruby. See the [official documentation](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) for details. See [ARCHITECTURE.md](ARCHITECTURE.md) for how Boxwerk uses `Ruby::Box` internally.

## Quick Start

Create packages with `package.yml` files:

```
my_app/
├── package.yml
├── main.rb
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
gem install boxwerk
RUBY_BOX=1 boxwerk run main.rb
```

No Bundler or Gemfile required for basic usage. To use global or per-package gems, see [USAGE.md](USAGE.md).

## CLI

```
boxwerk run <script.rb>             Run a Ruby script in a package box
boxwerk exec <command> [args...]    Execute a command in the boxed environment
boxwerk console                     Interactive console in a package box
boxwerk info                        Show package structure and dependencies
boxwerk install                     Install gems for all packages
```

Options: `--package <package>`, `--all`, `--global`. See [USAGE.md](USAGE.md) for details.

## Limitations

- `Ruby::Box` is experimental in Ruby 4.0
- No constant reloading (restart required for code changes)
- IRB autocomplete disabled in console

See [TODO.md](TODO.md) for plans to address these and other planned features.

## Examples

- [`examples/minimal/`](examples/minimal/) — Three packages, dependency enforcement, no gems
- [`examples/complex/`](examples/complex/) — Namespaced constants, privacy, per-package gems, tests
- [`examples/rails/`](examples/rails/) — Usage with Rails

## Development

```bash
bundle install                        # Install dependencies
RUBY_BOX=1 bundle exec rake           # Run all tests (unit, e2e, examples)
bundle exec rake format               # Format code
```

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
