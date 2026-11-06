# Changelog

What changed between versions, for people using the plugin. A version names the
plugin, the runtime and the well-known types together, and upgrading means generating
your code again. The [version rules](docs/versions.md) say what each
kind of bump promises.

## 0.1.0 (unreleased)

The first version. Built and tested with protoc 27.0 to 36.2 and Goose v2026.3, and its
generated code needs a runtime of the same version (`abi 1`, as
`protoc-gen-goose --version` prints).

### Added

- Generated code for the binary wire format: proto2, proto3 and editions up to 2026 (2024 needs protoc 32.0 or later, and 2026 needs 36.0),
  with everything in the [README's table](README.md#what-it-covers).
- The runtime package `pb_wire`, and the well-known types under `pb_wire.wkt`.
- `pb_error_text`, which gives a decode error code as text.
- A limit on what one decode may allocate, 512 MiB unless `pb_set_decode_limit` changes
  it. Input that needs more gets `PB_ERR_TOO_LARGE`, where it could end the program.
- `--version` and `--help` on the plugin.
- Windows x64, for the plugin and the runtime, with [some limits](docs/install.md#windows).
- `M_f_len` and `M_f_at` for repeated fields, and `M_f_len`, `M_f_key_at` and
  `M_f_value_at` for maps, to go through them by index.
- `E_name(v)` for each enum, which gives a value's name as text. It takes the suffix
  `_name`, so a top-level `E_name` beside an enum `E`, or a field `E_name` of the
  message that holds it, is now a clash.

### Breaking

No version came before this one, but code written against the repository may use
what follows.

- The plain getter `M_f(m)` is gone from repeated string, bytes and message fields and
  from maps. It handed out an internal type, and looping over it printed that type
  rather than the text. Use `M_f_len`, `M_f_at`, `M_f_key_at` and `M_f_value_at`. The
  getter of repeated numeric, bool and enum fields stays.
