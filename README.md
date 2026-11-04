# goose-protobuf

`protoc-gen-goose` is a `protoc` plugin that generates
[Goose](https://aardappel.github.io/goose/) code for the **protobuf binary
wire format**. It is tested against the official protobuf conformance suite.

Status: Phase 3 in progress. The plugin emits one `.goose` file per `.proto`
file. For proto3 messages it stores scalars, enums, strings, bytes,
sub-messages (recursive and imported ones too) and repeated fields of all of
those (packed or not), oneofs as ADTs and maps, with `optional` presence and
unknown fields kept. Proto2 is kept as unknown fields until Phase 4. The well-known types are generated and committed in `wkt/`; `tests/roundtrip/wkt` covers them. Every
required proto3 binary conformance test passes. The backlog lives in beads
(`bd ready`).

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
pb_wire.goose   entry of the pb_wire package (this repository)
runtime/        pb_wire.goose: shared wire-format primitives
wkt/            well-known types, generated and committed (scripts/wkt.sh)
conformance/    Goose testee + failure list (may only shrink)
tests/          golden/, protos/, roundtrip/, fuzz/
third_party/    protobuf (submodule, pinned; conformance runner source)
scripts/        build_runner.sh, build_testee.sh, run_conformance.sh, test harnesses
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

The root file of a program names this repository as the `pb_wire` package:
`import pb_wire from "../goose-protobuf";` for a checkout. Well-known types
come from the package, not from protoc: a field of type
`google.protobuf.Duration` generates `import pb_wire.wkt.duration;`, and the
plugin writes nothing for `google/protobuf/duration.proto`
([decision 0007](docs/decisions/0007-well-known-types.md)).

Conformance:

```sh
git submodule update --init --checkout
scripts/build_runner.sh                            # once: builds the runner
scripts/run_conformance.sh                         # builds + runs build/testee
scripts/run_conformance.sh --maximum_edition 2023  # runner flags pass through
scripts/run_conformance.sh path/to/testee --test <name> --enforce_recommended
scripts/test_run_conformance.sh                    # checks the exit-code contract
```

With no testee argument (or a flag first), `run_conformance.sh` builds
`build/testee` with `scripts/build_testee.sh`, which generates
`TestAllTypesProto3` and the `conformance.proto` envelope with the plugin and
builds `conformance/testee.goose` against them. It exits nonzero iff a test fails that is not in
`conformance/failure_list_goose.txt`, or a listed test passes.

## License

MIT, see [LICENSE](LICENSE).
