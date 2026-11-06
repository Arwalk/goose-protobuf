# goose-protobuf

`protoc-gen-goose` is a `protoc` plugin that generates
[Goose](https://aardappel.github.io/goose/) code for the **protobuf binary
wire format**. It is tested against the official protobuf conformance suite.

Status: Phase 6 complete. The plugin emits one `.goose` file per `.proto`
file. For proto3 messages it stores scalars, enums, strings, bytes,
sub-messages (recursive and imported ones too) and repeated fields of all of
those (packed or not), oneofs as ADTs and maps, with `optional` presence and
unknown fields kept. proto2 messages store the same fields, with presence on
singular ones, and groups, like sub-messages. An unset field reads as its
default, a missing required field fails decoding, and enums are closed: a value
an enum does not declare stays an unknown field, as extensions do. The
well-known types are generated and committed in `wkt/`; `tests/roundtrip/wkt`
covers them. Every
required binary conformance test passes for proto3, proto2 and editions up to
2023, whose fields go through the same code, driven by their resolved features.
The generator is itself written in Goose.
The backlog lives in beads
(`bd ready`).

## Scope

- In scope: the binary wire format for proto2, proto3 and editions (up to
  2023), well-known types, and unknown-field preservation.
- Out of scope: JSON, text format, reflection, services/RPC.

## Usage

[docs/usage.md](docs/usage.md) goes from a `.proto` file to a running program.
[docs/README.md](docs/README.md) lists every document and who it is for.
Pinned versions are listed in [TOOLCHAIN.md](TOOLCHAIN.md).

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers building, testing and the repository's layout.

## License

MIT, see [LICENSE](LICENSE).
