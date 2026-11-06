# Versions and compatibility

What you can rely on when you upgrade, and what each kind of version bump means.

This project is before version 1.0. Until then, a breaking change bumps the middle
number (`0.Y.0`) and anything else bumps the last, breaking changes are listed in
[the changelog](../CHANGELOG.md), and they are made only with a reason. From 1.0 on,
the table under [What a version promises](#what-a-version-promises) applies.

## One version for everything

One tag, `vX.Y.Z`, names the plugin, the runtime and the well-known types. They are
only known to work together, and generated code does not build against a runtime of
another version.

**So upgrading means generating your code again.** Install the plugin of the new
version, run `protoc`, and import the runtime of the same version. What stays stable is
the code you write against generated names, not generated files. Do not edit them, or
diff them across versions.

## What you can rely on

| | |
|---|---|
| Generated names | [The naming rules, and every function listed in the reference](generated-code.md) |
| Record fields | Those of scalar and enum fields, and a oneof's field with its member names, including `pb_none` |
| Runtime | `PB_OK`, the `PB_ERR_*` codes with their values, `PB_MAX_DEPTH`, `pb_error_text`, `PB_DEFAULT_DECODE_LIMIT` and `pb_set_decode_limit` |
| Packages | The package name `pb_wire`, and the paths `pb_wire.wkt.*` with the names in them |
| Plugin | Its name, `--version` and `--help`, and that it takes no parameter: an unknown one is an error |
| Scripts | `install_plugin.sh`, `install_toolchain.sh` and `vendor_runtime.sh`: their arguments and what they install |
| Wire format | What protobuf itself promises: any version reads what another wrote |

## What may change in any release

If your code can reach something that the documentation does not name, it is not a
promise, whatever it looks like:

- Every other `pb_` and `PB_` name in the runtime, such as `pb_Span` and `pb_Reader`.
- Record fields starting with `pb_`, such as `pb_has0`, and the record fields of
  strings, bytes, sub-messages, repeated fields and maps. Use their accessors.
- `_decode_from`, and the generated `_Ref`, `_pool` and `_links` declarations.
- The text and bytes of generated code, including its comments.
- The plugin's `wkt` parameter, which only builds this repository.
- The order of fields and map entries in encoded bytes, beyond what protobuf promises,
  and which error code you get for input that is wrong in several ways.
- Every other script.

## What a version promises

| Bump | When |
|---|---|
| Major | A public name goes or changes meaning, a supported input stops being accepted, or a release requires a newer tool than the last one did |
| Minor | A public name or a capability is added |
| Patch | Fixes and internal changes only |

Two cases that may surprise you:

- **A fix towards protobuf's behaviour is a patch**, even if your program relied on the
  bug, as protobuf's behaviour is what this project promises.
- **A new accessor is a minor, and can clash with your names.** It may change how a
  message or field whose name ends in its suffix is escaped, or clash with a global
  name of yours if your proto has no package. The changelog names the suffix. Give
  your protos a package to avoid the second case.

Each release is tested with [the tool versions in the install guide](install.md#requirements),
and others are not promised to work.
