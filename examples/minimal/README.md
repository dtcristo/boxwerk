# Minimal Boxwerk Example

Three packages demonstrating dependency enforcement — no Bundler required.

```
.                    → depends on foo, bar
packs/foo            → no dependencies
packs/bar            → depends on baz
packs/baz            → no dependencies
```

Root can access `Foo` and `Bar` (direct dependencies) but not `Baz` (transitive).

## Run

```bash
RUBY_BOX=1 bin/boxwerk run main.rb
```
