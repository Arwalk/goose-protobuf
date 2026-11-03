# goose-protobuf

`protoc-gen-goose` is a `protoc` plugin that generates
[Goose](https://aardappel.github.io/goose/) code for the **protobuf binary
wire format**. It is tested against the official protobuf conformance suite.

Status: Phase 1 in progress. The plugin emits one `.goose` file per `.proto` file,
with message structs (no fields yet) and enum constants; `runtime/pb_wire.goose`
has the scalar wire primitives. The backlog lives in beads (`bd ready`).

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
scripts/build_runner.sh                            # once: builds the runner
scripts/run_conformance.sh                         # builds + runs build/testee
scripts/run_conformance.sh --maximum_edition 2023  # runner flags pass through
scripts/run_conformance.sh path/to/testee --test <name> --enforce_recommended
scripts/test_run_conformance.sh                    # checks the exit-code contract
```

With no testee argument (or a flag first), `run_conformance.sh` builds
`conformance/testee.goose` to `build/testee` when it is missing or older
than its sources. It exits nonzero iff a test fails that is not in
`conformance/failure_list_goose.txt`, or a listed test passes.

## License

MIT, see [LICENSE](LICENSE).
