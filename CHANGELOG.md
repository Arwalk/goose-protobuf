# Changelog

What changed between versions, for people using the plugin. A version names the
plugin, the runtime and the well-known types together, and upgrading means generating
your code again. The [version rules](docs/decisions/0012-public-api.md) say what each
kind of bump promises.

## 0.1.0 (unreleased)

The first version. Built and tested with protoc v36.2 and Goose v2026.3, and its
generated code needs a runtime of the same version (`abi 1`, as
`protoc-gen-goose --version` prints).

### Added

- Generated code for the binary wire format: proto2, proto3 and editions up to 2023,
  with everything in the [README's table](README.md#what-it-covers).
- The runtime package `pb_wire`, and the well-known types under `pb_wire.wkt`.
- `pb_error_text`, which gives a decode error code as text.
- `--version` and `--help` on the plugin.
- `M_f_len` and `M_f_at` for repeated fields, and `M_f_len`, `M_f_key_at` and
  `M_f_value_at` for maps, to go through them by index.

### Breaking

No version came before this one, but code written against the repository may use
what follows.

- The plain getter `M_f(m)` is gone from repeated string, bytes and message fields and
  from maps. It handed out an internal type, and looping over it printed that type
  rather than the text. Use `M_f_len`, `M_f_at`, `M_f_key_at` and `M_f_value_at`. The
  getter of repeated numeric, bool and enum fields stays.
