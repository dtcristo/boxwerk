# Minimal Boxwerk Example

Three packages demonstrating dependency enforcement — no Gemfile required.

## Dependency Graph

```
.
├── packs/foo
└── packs/bar
    └── packs/baz
```

Root can access `Foo` and `Bar` (direct dependencies) but not `Baz` (transitive only).

## Run

```bash
RUBY_BOX=1 bin/boxwerk run main.rb
```
