# 0013: generated code outside the root directory

- Status: proposed for the project owner. (Since superseded: "nothing depends on it
  yet" no longer holds, as the usage guide shows this form and the consumer test holds
  it, so a different answer would change both.)
- Date: 2026-11-06
- Bead: gpb-ky7.6
- Toolchain: Goose v2026.3, protoc 36.2
- Builds on: [0005](0005-runtime-distribution.md), [0006](0006-naming.md)

## Question

Generated files import each other by bare name, `import b.y;`, which Goose resolves
from the root file's directory. So `--goose_out=gen` with `import gen.a.x;` fails, with
`cannot find the module b.y`. Real projects want a `gen/`, and a library may want to
ship generated code. Should the plugin get an `import_prefix`-style parameter?

## Decision

**No parameter.** A directory of generated code is a Goose package, which needs one line
from the user and nothing from the plugin:

```sh
mkdir -p gen
protoc -I protos --goose_out=gen a/x.proto b/y.proto
echo 'import .a.x;' > gen/gen.goose
```

```goose
import pb_wire from "../goose-protobuf";
import gen from "./gen";
```

A package's bare imports resolve from its own root, so the generated files are the
same bytes wherever they go. `scripts/consumer_test.sh` tests this form.

## What was measured

Each case generates `a/x.proto`, which imports `b/y.proto` and a well-known type, then
builds and runs a round trip through it, except where it says otherwise.

| Case | Result |
|---|---|
| `--goose_out=gen`, `import gen.a.x;` | `cannot find the module b.y` |
| `import gen from "./gen";`, with `gen/gen.goose` holding `import .a.x;` | **Works.** The binary is byte-identical to generating next to the root (78,232 bytes, same checksum) |
| The same, with an empty entry and `import gen.a.x;` in the root | `gen/a/x is both a file of this package ... and the declared package gen's module` |
| The same, with the package at `./src/gen` | Works, as `gen/a/x` is then no file of the root's |
| A package named unlike its directory: `import pb_gen from "./gen";`, `import pb_gen.a.x;` | Works |
| No entry file | `the package gen ... has no gen.goose` |
| A proto named `gen.proto`, so that it generates the entry | Works |
| Two packages holding the same proto path `a/x`, with `import g1.a.x;` in the root | The clash above, for each |
| Runtime vendored beside the root, generated code in a package | `cannot find the module pb_wire`: a package resolves from its own root |
| Runtime vendored into `gen/` | Works |
| A library package with generated code at its root, using the bare imports of today | Works, with `pb_wire` declared by the program |
| Such a library that requires `pb_wire`, in a program that does not declare it | A clear error, which names the line to add |
| Relative imports written by hand: `import .b;` from `api/a.goose`, `import .api.b;` from `c.goose` | Work, downwards and sideways |
| A relative import upwards: `import ..d;` | `expected identifier in import`: Goose has none |

## What a parameter would have added

Relative imports need no parameter, but cannot express `a/x` importing `b/y`, which is
what protos in sibling directories do. So they are out.

One case stays open. **A program's proto imports a proto whose code a library ships.**
The program's generated file says `import b.y;`, which is neither its own file nor a
module of a package named `b`:

| Case | Result |
|---|---|
| As generated | `cannot find the module b.y` |
| That import changed by hand to `import lib.b.y;` | Works |
| The library's package named `b`, with `b/y.goose` beside its entry | Works, until its files import each other: `cannot find the module b.z` |
| The program generates the library's proto too | `type name already declared`, once the library's copy loads as well |

What fixes it is a map from proto file to Goose module, as Go's `M` option is, as only
some imports move. A global `import_prefix` would move the program's imports of its own
files as well.

We do not add one, as:

- A library can ship its `.proto` files and let each program generate them, which is
  protobuf's usual way, and gives one copy of each type.
- The owner wants no further feature for now, and nobody has asked for this yet.
- It can come later with no change to generated code, as a new parameter, which the
  version rules of decision 0012 call a minor.

## Rejected

- **`import_prefix`:** the `gen/` case does not need it, and it does not solve the
  library case.
- **Relative imports in all generated code:** they cannot go upwards, and they would
  change every generated file for no gain.
- **A package entry that the plugin writes:** it would need to know which files are
  the top ones, and `protoc` runs would overwrite the user's entry.
