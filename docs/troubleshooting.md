# Troubleshooting

Find what you see below. The first section is for mistakes that give no error, so look
there if your program builds and runs but does the wrong thing.

## It builds, but the result is wrong

### A field I set is empty

```text
city=[] zip=0
```

You bound a message with `=`, which makes a copy, and set the fields of the copy. Goose
gives no warning. Bind with `.=` whatever returns a message you will change:

```goose
let home .= Person_mutable_home(p);    // not let home = ...
let friend .= Book_add_people(b);      // not let friend = ...
```

The same goes for `_put` of a map with message values, and for `_at`, `_value_at` and
the getter of a message, if you change what they return.

### Printing a field shows `pb_Span`

```text
pb_Span { 0, 1 }
```

`m.name` is where the string is in a pool, not the string. Read it with its function:
`print(Person_name(m))`. Only numbers, bools and enums are read as record fields
([the reference](generated-code.md) lists them by kind).

### Repeated values appear twice after decoding

`M_decode` merges into the message, as protobuf's merge does, so what was there stays.
Call `M_clear(m)` first, or decode into a new message.

### A message changed when I cleared or changed another

`let b = a;` copies a record, whose contents stay shared with `a`. Use `M_copy(b, a)`.

### A map has too many entries, or `_get` finds an old value

`M_f_append` does not look for the key, so a repeated key stays until you call
`M_fold_maps(m)`. Call it once, after the last append and before reading.

### A string I kept has changed

What a getter returns is a view of a pool, not a copy. Copy what you want to keep
([how long things stay valid](generated-code.md#how-long-things-stay-valid)).

## `goose build` fails

### Cannot find the module `pb_wire`

```text
error: cannot find the module pb_wire, looked for
```

Your root file has to say where the runtime comes from, and it has to say so itself,
even if only generated files use it:

```goose
import pb_wire from "../goose-protobuf";
```

[The install guide](install.md) has the three ways to get it.

### Cannot find the module of a generated file

```text
error: cannot find the module b, looked for
```

Goose resolves every import from the directory of your root file, including those
between generated files, so `--goose_out=gen` with `import gen.a;` fails. Generate next
to your root file with `protoc --goose_out=.`, or make the directory a package
([the usage guide](usage.md#generated-code-in-a-directory-of-its-own) shows how). If this
names one of your own protos, generate that file too.

### `pb_wire` is both a file and a package

```text
error: pb_wire is both a file of this package (pb_wire.goose) and the declared package pb_wire's module
```

You have a copy of the runtime next to your root file, and an `import ... from` line
too. Use one. Delete the copy, or write `import pb_wire;`.

The same message for your own directory, `gen/a is both a file of this package`, means
the root file imports `gen.a` as well as declaring the package `gen`. Remove that line,
and import `.a` from the package's entry, `gen/gen.goose`.

### The plugin and runtime versions differ

```text
error: unknown identifier: pb_plugin_and_runtime_versions_differ_abi_1
```

The generated code came from a plugin of another version than the runtime you import.
`protoc-gen-goose --version` shows which `abi` number your plugin writes.
Install the plugin of that version, generate again, and do not edit generated files.

### Unknown function, for a field's getter

```text
error: unknown function: p::P_tags
```

Repeated strings, bytes and messages and maps have no getter of all their values. Use
`_len` and `_at`, and for a map `_key_at` and `_value_at`:

```goose
for i in P_tags_len(m) { print(P_tags_at(m, i)); }
```

### Expected a value of type `pb_Span`

```text
error: expected a value of type pb_Span, got const u8[:]
```

You wrote `m.name = "x"` to a string or bytes field. Use the setter:
`Person_set_name(m, "x")`.

### Cannot pass `Sub?` as `Sub&`

```text
cannot pass p::Sub? as p::Sub&
```

The getter of a sub-message returns null if it is not set, so check it first:

```goose
let home .= Person_home(p);
guard home else { return; }
print(Address_city(home));
```

Or use `Person_mutable_home(p)`, which sets an empty one if there is none.

### Cannot construct a value with a literal

```text
error: cannot construct a value of type P with a literal
```

Your proto has a package, and its types are in that namespace: `p::P { .. }`.

### Match does not cover a variant

```text
error: match does not cover variant P_o.pb_none
```

A match on a oneof needs each member, and `pb_none` for no member set, or a `_` arm.

## `protoc` fails

### The plugin is not found

```text
protoc-gen-goose: program not found or is not executable
```

`protoc` looks for the plugin on your `PATH`. Run `scripts/install_plugin.sh` and put
the directory it names on your `PATH`, or say where it is:
`--plugin=protoc-gen-goose=path/to/protoc-gen-goose`.

### The output directory does not exist

```text
gen/: No such file or directory
```

`protoc` does not create the directory that `--goose_out` names. Create it first.

### An import is not found

```text
missing.proto: File not found.
```

`protoc` looks for imports in the directories that `-I` names, and in the current one
if there is no `-I`. Add the directory that holds the file. The well-known types
(`google/protobuf/*.proto`) come with `protoc`.

### A newer edition is refused

```text
is a file using edition 2026, which isn't supported by code generator protoc-gen-goose.
```

Editions up to 2024 are supported ([limitations](limitations.md)).

If `protoc` itself says that edition 2024 is later than its maximum, your `protoc` is
older than 32.0, which edition 2024 files need.

### Two names map to one

```text
both map to the Goose name A_B
```

Two things in your proto have the same generated name, here `A.B` and a top-level
`A_B`, and no files were written. Rename one
([the naming rules](generated-code.md#names)).

### An unknown parameter

```text
--goose_out: unknown parameter: foo
```

The plugin takes no parameter, so write `--goose_out=DIR`, with nothing before a `:`.
