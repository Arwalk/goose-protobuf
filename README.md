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

## Design

- The generator is written in Goose (`generator-goose/`). It reads
  `descriptor.proto` / `plugin.proto` through bindings it generates itself, which
  are committed, so a checkout builds with Goose alone
  ([decision 0011](docs/decisions/0011-goose-only-generator.md)).
- Generated code is self-contained per message: `encode`, `decode` and
  `size_of`. The only shared code is `runtime/pb_wire.goose`, which holds
  the wire primitives.
- Goose has no heap, so message storage uses pools and handles. The layout
  is decided by a spike, recorded in `docs/decisions/`.

## Layout

```
generator-goose/ protoc plugin (protoc-gen-goose), with its own bindings
pb_wire.goose   entry of the pb_wire package (this repository)
runtime/        pb_wire.goose: shared wire-format primitives
wkt/            well-known types, generated and committed (scripts/wkt.sh)
conformance/    Goose testee + failure list (may only shrink)
tests/          golden/, protos/, roundtrip/ (also the scripts/interop.sh corpus), fuzz/ (scripts/fuzz.sh), bench/
third_party/    protobuf (submodule, pinned; conformance runner source)
scripts/        build_runner.sh, build_testee.sh, run_conformance.sh, test harnesses
docs/decisions/ spike conclusions and design decisions
```

Pinned versions are listed in [TOOLCHAIN.md](TOOLCHAIN.md).

## Usage

[docs/usage.md](docs/usage.md) goes from a `.proto` file to a running program.

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

Fuzzing runs the generated decoders under libFuzzer and AddressSanitizer, over the
conformance suite's messages, so it needs the protobuf submodule too, and clang with
its fuzzer runtime:

```sh
sudo apt-get install --no-install-recommends clang libclang-rt-dev   # Ubuntu
scripts/fuzz.sh 120                                # builds + fuzzes for 120 seconds
FUZZ_REBUILD=0 scripts/fuzz.sh 3600                # keeps the fuzz binary
scripts/test_fuzz.sh                               # checks that a crash is reported
```

A crash exits nonzero and leaves its input in `build/fuzz/`. Plain clang is not enough
on Ubuntu, as the runtime is a package of its own.

## License

MIT, see [LICENSE](LICENSE).
