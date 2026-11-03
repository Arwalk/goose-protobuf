# 0006: naming of generated Goose code

- Status: final (options chosen by the project owner, 2026-11-03)
- Date: 2026-11-03
- Bead: gpb-41j.3 (generator core and Goose emitter)
- Builds on: [0001](0001-message-layout.md) (storage layout),
  [0004](0004-decode-errors.md) (decode errors)

## Question

How do protobuf packages, messages, enums, fields, generated functions
and output files map to Goose names? User code, goldens and the testee
all depend on these names, so they are fixed once, here.

Goose facts this rests on:

- **Verified:** `namespace x;` works, with an `import` after it and
  qualified use (`x::Name`). A namespaced file's unqualified calls fall
  back to the global namespace, so the `pb_*` runtime functions resolve.
- **Verified:** an empty struct works as a local.
- **Verified:** an `i32` constant of `-2147483648` typechecks.
- **Verified:** Goose has overload sets.
- **Verified:** `import a.b.c;` loads `a/b/c.goose` (reference §21).
- **Not verified:** nested namespaces, method-call syntax on user
  functions, and overload resolution across many message types.

## Decision

| Element | Rule | Example |
|---|---|---|
| Package | One namespace, with the package's parts joined by `_`. No package means the global namespace. | `foo.bar` → `namespace foo_bar;`, used as `foo_bar::Outer` |
| Message | Nested names joined by `_` | `Outer.Inner` → `struct Outer_Inner` |
| Enum | `i32` constants named `<enum path>_<VALUE>`. Aliases get their own constants. No prefix stripping. | `Outer.Color.COLOR_RED` → `let Outer_Color_COLOR_RED: i32` |
| Generated functions | Free functions named `<message>_<operation>` | `Node_decode`, `Node_encode`, `Node_size_of`, `Node_clear` |
| Accessors | `<message>_<field>` plus the operation | `Node_name`, `Node_set_name`, `Node_children_at`, `Node_attrs_get` |
| Record fields | Proto field names, escaped | `type` → `type_` |
| Reserved names | Any final name on the reserved list gets a trailing `_` | `message type` → `type_`; `struct.self` → `struct_self` |
| Collisions | Two declarations that end up with the same Goose name produce `CodeGeneratorResponse.error` and no files. protoc still exits 0. | `A.B` and a top-level `A_B` |
| Output files | Each path segment of the `.proto` name with `-` and `.` replaced by `_`, then escaped. Two protos that map to the same output path are a collision error. | `api/foo.v1.proto` → `api/foo_v1.goose`, imported as `import api.foo_v1;` |

### The reserved list

Escaping applies to the **final** name only, never to the parts it was
built from. It covers:

- Goose keywords and contextual keywords (reference, Appendix A);
- Goose builtins (reference §25), such as `print`, `str`, `copy`,
  `abort`, `assert` and `exit`;
- names starting with `pb_`, which belong to the runtime;
- names that would clash with a generated function or accessor. A
  nested declaration whose path ends in a generated suffix (`_decode`,
  `_encode`, `_size_of`, `_clear`, `_set_<field>`, `_<field>_at`,
  `_<field>_get`, `_<field>_put`, ...) is escaped, and so is a nested
  name equal to an accessor of its parent (message `Node.children` next
  to field `children`).

The emitter checks every generated name, types, constants and
functions alike, against the names already claimed in the file. A clash
that escaping cannot resolve is a collision error.

## Why

- **One namespace per package (rather than prefixes or nothing).**
  Goose builds whole programs, so two packages with the same message
  name must not clash. A namespace gives that, and names stay short
  inside the package's own file. Nested namespaces are probably not
  supported, and per-name prefixes (upb style) waste a feature built
  for this. A plugin option to override the namespace, like Go's
  `go_package`, can be added later without breaking anything.
- **`Outer_Inner` and `Enum_VALUE` (C++ style).** Familiar from
  protobuf C++ and Go. Unique, because protobuf already makes value
  names unique within a scope. The stutter that comes with the
  recommended style (`Color_COLOR_RED`) is accepted, as in C++.
  Prefix stripping, like buf's TypeScript plugins, has corner cases (a
  stripped name starting with a digit, a stripped name that collides,
  enums that don't follow the convention), and the rule would have to
  be exactly deterministic.
- **Prefixed free functions (rather than overloads or method syntax).**
  Explicit, grep-friendly, and error messages name the exact function.
  This is the same choice as upb, the closest analogue (C, no methods).
  Overloads (`decode(buf, m)`) and method-call syntax (`m.decode(buf)`)
  are unverified at scale, and they risk clashing with user and stdlib
  functions. They could be added later as thin wrappers.
- **An extended reserved list (rather than keywords only).** Keywords
  alone miss three kinds of clash: with builtins, with the runtime, and
  between a nested type and a generated function (`Outer.decode` against
  `Outer_decode`). One rule, a trailing `_`, covers all of them, as C++
  protobuf does with `class_`.
- **Mangled file names (rather than kept as is or rejected).** A Goose
  import path is dotted, so `my-api.proto` or `foo.v1.proto` could
  otherwise never be imported by another generated file. Rejecting such
  names would turn away real-world protos.

## Rejected

- Package as a prefix on every name, with no namespace (upb style).
- No namespace and no prefix: cross-package clashes.
- Nested namespaces: probably unsupported.
- `Outer__Inner` (double underscore), and `OuterInner` (ambiguous).
- Bare enum values, and stripping the shared prefix from values.
- Overloaded `decode`/`encode`/`clear`, and method-call syntax, as the
  primary API.
- A leading `_` for escaping (reserved names in the C the code compiles
  to), and rejecting keyword names (real protos use `type`).
- Output file names kept as they are, or rejected when not importable.

## Status of the implementation

gpb-41j.3 implemented the package, message, enum and keyword rules, and
collision detection for types and constants. Still to do:

- gpb-41j.9: extend the reserved list to builtins, `pb_` names and
  generated function names, and check functions for collisions;
- gpb-8qn.8: output file name mangling.
