# goose-protobuf

`protoc-gen-goose` is a `protoc` plugin that generates
[Goose](https://aardappel.github.io/goose/) code for the **protobuf binary
wire format**. It is tested against the official protobuf conformance suite.

Status: plugin skeleton (decodes the request, emits no files). The backlog lives in beads (`bd ready`).

## Scope

- In scope: the binary wire format for proto2, proto3 and editions (up to
  2023), well-known types, and unknown-field preservation.
- Out of scope: JSON, text format, reflection, services/RPC.

## Design

- The generator is written in Zig (`generator/`). It reads
  `descriptor.proto` / `plugin.proto` through
  [zig-protobuf](https://github.com/Arwalk/zig-protobuf). Self-hosting in
  Goose is a late, optional phase.
- Generated code is self-contained per message: `encode`, `decode` and
  `size_of`. The only shared code is `runtime/pb_wire.goose`, which holds
  the wire primitives.
- Goose has no heap, so message storage uses pools and handles. The layout
  is decided by a spike, recorded in `docs/decisions/`.

## Layout

```
generator/      Zig protoc plugin (protoc-gen-goose)
runtime/        pb_wire.goose: shared wire-format primitives
conformance/    Goose testee + failure list (may only shrink)
tests/          golden/, protos/, roundtrip/, fuzz/
third_party/    protobuf (submodule, pinned; conformance runner source)
scripts/        build_runner.sh, run_conformance.sh
docs/decisions/ spike conclusions and design decisions
```

Pinned versions are listed in [TOOLCHAIN.md](TOOLCHAIN.md).

## Planned usage

```sh
(cd generator && zig build)
protoc --plugin=protoc-gen-goose=generator/zig-out/bin/protoc-gen-goose \
       --goose_out=out/ -I protos protos/foo.proto
goose build app.goose        # app.goose imports out/foo.goose + pb_wire
```

Conformance:

```sh
git submodule update --init
scripts/build_runner.sh
scripts/run_conformance.sh build/testee
```

## License

MIT, see [LICENSE](LICENSE).
