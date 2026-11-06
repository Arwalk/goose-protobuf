# Contributing to goose-protobuf

This guide is for people changing the generator, the runtime or the tests. To use
the plugin in your own project, start from the [README](README.md) instead.

The project generates Goose code for the protobuf **binary wire format only**, and
the conformance suite is the measure of correctness.

## Set up

```sh
scripts/install_toolchain.sh          # pinned protoc, Goose and Python protobuf, in .tools/
export PATH="$PWD/.tools/bin:$PATH"
scripts/build_plugin.sh               # the generator, to build/protoc-gen-goose
```

[TOOLCHAIN.md](TOOLCHAIN.md) lists the pinned versions and their caveats. A pin
changes only in a dedicated commit that updates TOOLCHAIN.md, CI, and any affected
goldens and failure list.

The protobuf submodule, which only the conformance and fuzz tests use, is left out
of a plain `git submodule update --init`, so that package users do not fetch it.
Ask for it by name:

```sh
git submodule update --init --checkout
```

## Layout

```
generator-goose/ protoc plugin (protoc-gen-goose), with its own bindings
pb_wire.goose   entry of the pb_wire package (this repository)
runtime/        pb_wire.goose: shared wire-format primitives
wkt/            well-known types, generated and committed (scripts/wkt.sh)
conformance/    Goose testee + failure lists (may only shrink)
tests/          golden/, protos/, roundtrip/ (also the scripts/interop.sh corpus),
                runtime/, selfhost/, fuzz/ (scripts/fuzz.sh), bench/, spikes/
third_party/    protobuf (submodule, pinned; conformance runner source)
examples/       programs for users; scripts/check_docs.py runs each README
scripts/        build, test and check scripts, listed below
docs/decisions/ spike conclusions and design decisions
```

## Design

- The generator is written in Goose (`generator-goose/`). It reads
  `descriptor.proto` / `plugin.proto` through bindings it generates itself, which
  are committed, so a checkout builds with Goose alone
  ([decision 0011](docs/decisions/0011-goose-only-generator.md)).
- Generated code is self-contained per message: `encode`, `decode` and `size_of`.
  The only shared code is `runtime/pb_wire.goose`, which holds the wire primitives.
- Goose has no heap, so message storage uses pools and handles
  ([decision 0001](docs/decisions/0001-message-layout.md)).

[docs/decisions/](docs/decisions/) records why, and
[docs/README.md](docs/README.md) says where each fact in the docs belongs.

## Build and test

Every CI step runs a script that also runs locally.

```sh
goose check runtime/pb_wire.goose               # Goose typecheck
scripts/build_plugin.sh                         # the generator, to build/protoc-gen-goose
scripts/install_plugin.sh [prefix]              # build it and copy it to <prefix>/bin (default ~/.local)
tests/smoke_plugin.sh                           # protoc runs the plugin; bad input is refused
scripts/golden.sh                               # golden tests (--update to accept)
scripts/goose_tests.sh [paths]                  # Goose unit tests (tests/**/*_test.goose)
scripts/roundtrip.sh [names]                    # round-trip tests (tests/roundtrip/<name>/)
scripts/interop.sh [names]                      # the same cases through Goose, protoc and Python
scripts/regen_bindings.sh [--update]            # the plugin writes its own bindings unchanged
scripts/selfhost_bindings.sh                    # plugin bindings on real CodeGeneratorRequests
scripts/selfhost_tests.sh                       # unit tests of generator-goose/ (tests/selfhost/*_unit.goose)
scripts/consumer_test.sh                        # consume this repo from outside: vendored, path, git
scripts/install_buf.sh                          # once: the pinned buf, which the next line needs
scripts/check_docs.py                           # run README and the guides: snippets, commands and output
scripts/check_links.py                          # relative links in tracked Markdown reach a file and heading
scripts/check_reference.py                      # docs/generated-code.md matches tests/golden/
scripts/check_troubleshooting.py                # the messages in docs/troubleshooting.md are real
scripts/check_generated.sh [-I dir] protos      # generate + goose check, no golden
scripts/wkt.sh                                  # wkt/ matches the plugin (--update to accept)
scripts/edition_defaults.sh                     # feature defaults match protoc (--update to accept)
scripts/protoc_versions.sh [versions]           # goldens and round trips on each supported protoc
scripts/bench_maps.sh [sizes]                   # map decode timings (decision 0008)
scripts/bench_generator.py [--check] [shapes]   # the plugin's time and memory on large requests
```

Helpers these use, which you can also run alone:

```sh
scripts/proto_closure.sh [-I dir] protos        # the given protos and all they import
scripts/vendor_runtime.sh <dir>                 # copy the pb_wire package into a program
```

These self-test the harnesses, by checking that each one catches a failure:

```sh
scripts/test_golden.sh
scripts/test_goose_tests.sh
scripts/test_roundtrip.sh
scripts/test_interop.sh
scripts/test_fuzz.sh
scripts/test_check_docs.sh
scripts/test_check_links.sh
scripts/test_check_reference.sh
scripts/test_check_troubleshooting.sh
scripts/test_consumer_test.sh
scripts/test_check_generated.sh
scripts/test_install_plugin.sh
scripts/test_selfhost_tests.sh
scripts/test_run_conformance.sh
scripts/test_protoc_versions.sh
```

### Golden tests

Each `tests/protos/<name>.proto` is generated twice (the two outputs must be
byte-identical), diffed against `tests/golden/<name>/` (no directory means no
files), and every golden `.goose` file goes through `goose check` next to a copy of
`runtime/pb_wire.goose` and the generated files it imports.

After an intended generator change, run `scripts/golden.sh --update` and review the
golden diff in the commit, and the same with `scripts/wkt.sh --update` for the
well-known types in `wkt/`.

### Goose unit tests

A `*_test.goose` file under `tests/` is a program built with `--debug` and run. It
passes iff it exits 0 (fail with `abort(...)`). Import the runtime as a directory
package, since a plain `import` cannot reach above the test's directory:
`import pb_wire from "../../runtime";`.

### Generator unit tests

A `tests/selfhost/*_unit.goose` file is such a program too, built by
`scripts/selfhost_tests.sh` next to the files of `generator-goose/`, its bindings and
`unit_support.goose`, so it calls the generator's functions directly. They are named
`*_unit.goose`, not `*_test.goose`, as they cannot build where they are.

### Round-trip tests

`tests/roundtrip/<name>/` holds `<case>.txtpb` files, each with a
`# proto-message: pkg.Msg` line, and a `<name>_roundtrip.goose` program. The harness
generates `tests/protos/<name>.proto` and the files it imports next to them, encodes
each case with `protoc --encode` into `<case>.bin`, which the program embeds with
`embed_file`, then builds and runs the program. It passes iff it exits 0.

### Interop tests

`scripts/interop.sh` needs no program. It runs every round-trip `.txtpb` through a
generated echo (decode, encode), checking what comes out with `protoc --decode` and
Python protobuf, and what those encode back through the echo. Goose's bytes must
equal Python's deterministic ones, so a case whose message Goose only partly knows
says `# interop-decode-as: pkg.Msg`. A mismatch prints a hex diff.

### Conformance

```sh
git submodule update --init --checkout
scripts/build_runner.sh                            # once: builds the runner
scripts/run_conformance.sh                         # builds + runs build/testee
scripts/run_conformance.sh --maximum_edition 2024  # runner flags pass through
scripts/run_conformance.sh path/to/testee --test <name> --enforce_recommended
FAILURE_LIST=conformance/failure_list_recommended.txt scripts/run_conformance.sh \
  build/testee --maximum_edition 2024 --enforce_recommended   # recommended tests too
scripts/test_run_conformance.sh                    # checks the exit-code contract
```

With no testee argument (or a flag first), `run_conformance.sh` builds `build/testee`
with `scripts/build_testee.sh`, which generates `TestAllTypesProto3` and the
`conformance.proto` envelope with the plugin and builds `conformance/testee.goose`
against them. It exits nonzero iff a test fails that is not in
`conformance/failure_list_goose.txt`, or a listed test passes.
[TOOLCHAIN.md](TOOLCHAIN.md) has what the runner needs to build.

### Fuzzing

Fuzzing runs the generated decoders under libFuzzer and AddressSanitizer, over the
conformance suite's messages, so it needs the protobuf submodule too, and clang with
its fuzzer runtime:

```sh
sudo apt-get install --no-install-recommends clang libclang-rt-dev   # Ubuntu
scripts/fuzz.sh 120                                # builds + fuzzes for 120 seconds
FUZZ_REBUILD=0 scripts/fuzz.sh 3600                # keeps the fuzz binary
scripts/test_fuzz.sh                               # checks that a crash is reported
scripts/fuzz_seeds.sh                              # refresh the seeds, after a suite or pin change
```

A crash exits nonzero and leaves its input in `build/fuzz/`. Plain clang is not
enough on Ubuntu, as the runtime is a package of its own.

## Rules

- **Commits** follow Conventional Commits. The subject is 50 characters or fewer,
  capitalised after the type, imperative, with no trailing period, e.g.
  `feat: Emit packed repeated fields`. Wrap the body at 72 columns; it explains what
  changed and why.
- **Bug fixes are test-first**: write the failing test, run it and watch it fail,
  then fix.
- **The plugin is built on its own output.** After a change to what the generator
  emits, run `scripts/regen_bindings.sh --update` until it reports no change, and
  commit `generator-goose/google/` with the goldens
  ([decision 0011](docs/decisions/0011-goose-only-generator.md)).
- **Generated code must pass `goose check`.** Goose has no formatter and no
  `goose test`, so generator output must be byte-deterministic (same input, same
  bytes), and golden tests check that.
- **The conformance failure lists may only shrink.** Never add an entry to
  `conformance/failure_list_goose.txt` or `conformance/failure_list_recommended.txt`
  to make CI pass. A newly failing test is a bug.
- **Spike conclusions** go in `docs/decisions/` as `NNNN-short-title.md`, with a line
  in [its index](docs/decisions/README.md).
- **Work is tracked in beads**, in a database kept apart from the repository's files.
  To look up a `gpb-` id in a document or commit, run `bd bootstrap` in a clone. There
  are no TODO comments or lists without a bead id.

## Changing the plugin and runtime version check

Each generated file needs a name from the runtime,
`pb_plugin_and_runtime_versions_differ_abi_N`, so a plugin and a runtime of different
versions do not build together. Change `N` when generated code from before a change
would no longer work with the runtime after it, and at least for each release in
which `runtime/` or the generated code changed.

The plugin is built on its own output, so changing both at once would leave it unable
to build. In this order:

1. In `runtime/pb_wire.goose`, add the new name beside the old one.
2. In `generator-goose/emit.goose`, change `runtime_abi`.
3. Run `scripts/regen_bindings.sh --update` until it reports no change, then
   `scripts/golden.sh --update` and `scripts/wkt.sh --update`.
4. Remove the old name, and run `scripts/regen_bindings.sh` to check that the plugin
   still builds.

## Goose pitfalls

- Goose `varint` is not the protobuf varint. Do zigzag and varint maths in `u64`,
  and use `as!` for wrapping casts (`as` aborts under `--debug`).
- `T?` is a nullable reference, so field presence uses has-bits.
- `let x = f()` copies a record, and `let x .= f()` binds it.
- Enums have no discriminants, so protobuf enums are `i32` constants.
