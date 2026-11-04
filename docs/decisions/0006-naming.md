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
| Collisions | Two declarations that end up with the same Goose name produce `CodeGeneratorResponse.error` and no files. The plugin exits 0; protoc prints the error and exits 1. | `A.B` and a top-level `A_B` |
| Output files | Each path segment of the `.proto` name with `-` and `.` replaced by `_`, then escaped. Two protos that map to the same output path are a collision error. | `api/foo.v1.proto` → `api/foo_v1.goose`, imported as `import api.foo_v1;` |

### The reserved list

Escaping applies to the **final** name only, never to the parts it was
built from. It covers:

- Goose keywords and contextual keywords (reference, Appendix A);
- Goose builtins (reference §25), such as `print`, `str`, `copy`,
  `abort`, `assert` and `exit`;
- names starting with `pb_` or `PB_`, which belong to the runtime
  (`pb_Span`, `PB_ERR_TRUNCATED`);
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
collision detection for types and constants. gpb-41j.9 added the rest of
the reserved list, in `generator/src/emit.zig`:

- Every generated function and global is claimed before any type or
  constant: per message `_decode`, `_encode`, `_size_of`, `_clear`,
  `_copy`, and the `_Ref`, `_pool` and `_links` of decision 0001; per
  field, the accessors in `fieldAccessors` (the one table of accessor
  names, which the field emitters must use), plus `has_`/`clear_` for
  fields with explicit presence.
- Generated names are built from the unescaped path and then escaped
  like any final name: `message pb_x` gives `pb_x_` and `pb_x_decode_`,
  `message type` gives `type_` and `type_decode`.
- A nested type or enum constant whose name is generated gets one `_`.
  A top-level one, or a name still taken after the `_`, is a collision.
- A scalar with presence (proto3 `optional`, gpb-41j.5) is read as
  `m.<f>` and written with `<M>_set_<f>`, which sets its has-bit; it
  also has `<M>_has_<f>` and `<M>_clear_<f>`. Has-bits live in record
  fields `pb_has<k>: u32`, which no proto field can take because `pb_`
  names are escaped.
- A singular message field (gpb-8qn.2) has `<M>_<f>`, which returns the
  sub-message or null; `<M>_mutable_<f>`, which first sets an empty one
  if there is none; and `<M>_has_<f>` and `<M>_clear_<f>`. Its link is
  its presence, so it takes no has-bit.
- The accessors of repeated fields (`<f>`, `<f>_at`, `add_<f>`) are
  provisional: 0001 does not fix them. The task that emits a field kind
  updates the table, its goldens and this note.

gpb-8qn.8 implemented output file names, with one addition to the rule
above: any character an identifier cannot hold is replaced, not only `-`
and `.`, and a segment starting with a digit gets a leading `_` (verified:
`import _3d;` works). Such a name would otherwise be just as unimportable.
