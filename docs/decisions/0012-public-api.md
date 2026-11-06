# 0012: what is public, and how versions move

- Status: accepted by the project owner, who made a raised tool pin a major after
  1.0. gpb-ky7.15 gave repeated string, bytes and message fields and maps the
  accessors in this record's public table, without a plain getter.
- Date: 2026-11-06
- Bead: gpb-ky7.1
- Builds on: [0005](0005-runtime-distribution.md) (one tag for everything),
  [0006](0006-naming.md) (generated names)

## Question

`runtime/pb_wire.goose` has about 65 top-level `pb_` and `PB_` names, with no
namespace and no split between public and internal, and generated files hold many
more. What may a user rely on, and what does a version number promise?

## Decision

**Public is what your code can name by following the documentation. Everything
else is internal, and may change in any release.**

### Public

| Surface | What |
|---|---|
| Generated names | The rules of decision 0006, and for each message: `_decode`, `_encode`, `_size_of`, `_clear`, `_copy`, `_is_initialized`, `_fold_maps` where a map exists, and the field accessors (`_set_`, `_has_`, `_clear_`, `_mutable_`, `_add_`, `_at`, `_len`, `_key_at`, `_value_at`, `_get`, `_put`, `_remove`, `_append` and the plain getter, which repeated string, bytes and message fields and maps do not have) |
| Record fields | Those of scalar and enum fields, and a oneof's field with its member names, including `pb_none` |
| Runtime | `PB_OK`, the `PB_ERR_*` codes with their values, and `PB_MAX_DEPTH` |
| Packages | The package name `pb_wire`, and the paths `pb_wire.wkt.*` with the names in them |
| Plugin | The binary's name, and that it takes no parameter: an unknown one is an error |
| Scripts | `install_plugin.sh`, `install_toolchain.sh` and `vendor_runtime.sh`: their arguments and what they install |
| Wire format | What protobuf itself promises: any version reads what another wrote |

### Internal

- Every other `pb_` and `PB_` name in the runtime, among them `pb_Span`,
  `pb_Reader` and `PB_WT_*`. The runtime marks where they start.
- The `pb_` record fields of a generated message (`pb_has0`, `pb_unknown`), and the
  record fields of strings, bytes, sub-messages, repeated fields and maps, which you
  reach through accessors.
- `_decode_from`, and the generated `_Ref`, `_pool` and `_links` declarations.
- The text of generated code, including its comments, and its bytes. Regenerate;
  do not edit or diff it across versions.
- The plugin's `wkt` parameter, which builds this repository's `wkt/`.
- The order of fields and map entries in encoded bytes, beyond what protobuf
  promises, and which code you get for input that is wrong in several ways.
- Every other script.

Runtime internals have no prefix of their own, because generated code calls them
from your namespace and renaming them all would change every generated file for no
user's benefit. A name's being reachable does not make it public.

### Versions

One tag, `vX.Y.Z`, names the plugin, the runtime and the well-known types, which are
only known to work together (decision 0005), and generated code does not build
against a runtime of another version. Upgrading means regenerating. The promise is about the code you write against generated names, not about keeping old
generated files working with a new runtime.

| Bump | When |
|---|---|
| Major | A public name goes or changes meaning, a supported input stops being accepted, or a tool pin is raised |
| Minor | A public name or a capability is added |
| Patch | Fixes and internal changes only |

- **Before 1.0**, a breaking change bumps the minor (`0.Y.0`) and anything else bumps
  the patch. Breaking changes are still listed in the changelog, and made only with
  a reason. 1.0 is when this table starts to bind.
- **A fix towards protobuf's behaviour is a patch**, even if a program relied on the
  bug, as protobuf's own behaviour is what we promise. So is a conformance fix.
- **New generated names can clash, and that does not make them breaking.** A new
  accessor may change how decision 0006 escapes a message or field whose name ends
  in its suffix, or clash with your own global name if your proto has no package.
  This cannot be excluded without freezing the generator, and is rare, so such an
  addition is a minor, and the changelog names the suffix. Use a package.
- **A raised pin is a major**, and so a minor before 1.0, as it can force users to
  upgrade their toolchain. Each release is tested with the versions in
  `TOOLCHAIN.md`, and others are not promised to work.

## Enforced by

- `tests/runtime/pb_wire_public_test.goose` holds the public runtime names and their
  values, so a change to one fails a test.
- Goldens show any change to generated names in review.
- The guides, run in CI, use only public names.

## Rejected

- **Renaming internals with a prefix such as `pb__`**: a diff across every golden and
  binding, for a difference comments can state. Goose has no visibility to enforce it
  with either way.
- **A namespace for the runtime**: generated code would have to qualify every call,
  for the same result.
- **Promising that generated code outlives the runtime it came from**: it would
  freeze the internals, which are what the generator is free to change.
