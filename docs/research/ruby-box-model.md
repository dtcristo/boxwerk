# Ruby box model

Checked against Ruby 4.0.7 on 2026-10-17. Ruby::Box remains experimental.

The primary implementation reference is the official [Ruby 4.0.7 source archive](https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.7.tar.gz). File and function names below refer to that archive. The [Ruby::Box documentation](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html) explains the intended model, but parts disagree with this release's implementation.

## Boxes and startup

Source facts from `box.c` and `ruby.c`:

- Master holds the initial definitions. Before root and main exist, `rb_current_box` and `rb_root_box` return master. Calling all bootstrap execution "root" hides this startup phase.
- `rb_initialize_mandatory_boxes` creates separate root and main boxes from master. Root supports runtime/library initialization. Main runs the command-line program.
- Ruby loads the gem prelude independently in root and main after creating them. `box_initialize` loads it again in each optional box, when gems are enabled. RubyGems is therefore box-local, rather than a single shared `Gem` module.
- Command-line `-r` libraries load in main through `require_libraries_in_main_box`. They do not become part of master or appear automatically in optional boxes.
- `Ruby::Box.new` creates an optional user box using master, even when called from main or another optional box. It does not clone the caller.

Upstream regressions cover these distinctions in `test/ruby/test_box.rb`: `test_boxes_have_different_rubygems`, `test_require_list_loaded_only_in_main_box`, `test_bundler_setup_loaded_only_in_main_box`, and `test_calling_root_box_methods_does_not_change_user_boxes_newly_created`.

## What is copied

Source facts:

- `box_entry_initialize` duplicates master's load-path and loaded-features arrays, plus their supporting lookup state. Later array changes are box-local.
- `box_initialize` immediately obtains a writable copy of `Object`'s class state and exposes that constant table through the box object. This captures the top-level constants available when that box is created. Mandatory root and main also establish their own `Object` state during startup.
- Class and module state uses copy-on-write, not a deep copy of Ruby objects. `internal/class.h` functions `RCLASS_EXT_READABLE_LOOKUP` and `RCLASS_EXT_WRITABLE_LOOKUP` use the original class state until a box-specific copy exists. `class.c` function `rb_class_duplicate_classext` copies method and constant tables when needed.

Consequences inferred from those mechanisms: a box is not a complete frozen snapshot of every class at creation. Some later master changes can remain visible through class state that a box has not copied. Top-level constant tables and load bookkeeping have different timing from those lazy copies. Objects referenced by copied constants are not automatically duplicated.

Observed on the installed Ruby 4.0.7 with `RUBY_BOX=1`:

- `Ruby::Box.current == Ruby::Box.main`; root, master, and main are distinct.
- A new top-level constant added to master appears in subsequently created optional boxes, but not in preexisting boxes, root, or main. Constants added to root or main do not appear in fresh optional boxes.
- `Object.object_id` matched in master, root, main, and an optional box. The isolated state is not a separate `Object` class object.
- An array assigned to a master constant is the same object in sibling optional boxes. Mutating it in one changes what the other sees.
- Master load-path and loaded-feature entries added between two box creations appear only in the later box. Their arrays are distinct objects.
- A later method added to built-in `String` in master appeared in a fresh optional box but not an existing one. A later method added to a class defined in master appeared in existing boxes too, including one that had reopened that class. Do not generalize one method-visibility result to every class.
- `Ruby::Box.master.eval('method(:puts).box')` returned master. This directly contradicts a blanket claim that built-in methods execute in root.

For example, run this in a fresh Ruby process with `RUBY_BOX=1`:

```ruby
master = Ruby::Box.master
before = Ruby::Box.new
master.eval('ResearchMarker = []; ResearchMarker << :master')
after = Ruby::Box.new
p before.const_defined?(:ResearchMarker) # false
p after::ResearchMarker                 # [:master]
after.eval('ResearchMarker << :optional')
p master::ResearchMarker                # [:master, :optional]
```

## Execution and loading

`vm_method.c` function `rb_method_definition_create` records the current box in each method definition. `vm.c` function `current_box_on_cfp` retrieves that defining box for method frames. Calling a method from another box does not transplant its code into the caller's box.

Loading has its own context. `rb_vm_loading_box` recognizes an explicit box receiver for `require`, `require_relative`, and `load`; `load.c` resolves `$LOAD_PATH` and `$LOADED_FEATURES` using that loading box. Avoid equating the caller, executing method, and loading box.

## Documentation inconsistencies and Boxwerk's use

The public documentation says master only supplies copies and does not execute code. Ruby 4.0.7 registers `Ruby::Box.master` in `Init_Box`, and `rb_box_eval` evaluates code in the receiver without excluding master. Upstream's `test_require_list_loaded_only_in_main_box` itself calls `Ruby::Box.master.eval`. Boxwerk deliberately uses this capability for its global application context.

The documentation also describes built-in methods as running in root. The startup and method-frame implementation above makes that too broad: methods defined during bootstrap can retain master as their defining box. Describe their definition context precisely rather than promising that every built-in call executes in root.

For Boxwerk, "global context" means its application context hosted in master. It is not another Ruby box type. Boxwerk's root package is an optional user box representing the project directory; it is distinct from both Ruby's root box and Ruby's main box. Global code must load before package-box creation when packages need its top-level constants and loaded-feature state. Eager loading addresses that ordering; changing master later is not a reliable way to update every existing box.

These conclusions are version-specific. Source inspection establishes the mechanisms and upstream test expectations; it does not establish that every gem, native extension, or mutable object is isolated.
