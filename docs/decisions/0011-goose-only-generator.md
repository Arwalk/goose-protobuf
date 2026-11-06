# 0011: the generator is written in Goose, on bindings it commits

- Status: accepted
- Date: 2026-11-06
- Bead: gpb-rv2
- Toolchain: Goose v2026.3, protoc 36.2

## Question

The plugin existed twice, in Zig and in Goose, and the Goose one was built on
bindings of `descriptor.proto` and `plugin.proto` that the Zig one generated at
build time. With Zig gone, how does a clean checkout build the plugin?

## Decision

The bindings are committed, in `generator-goose/google/`, and
`scripts/build_plugin.sh` needs only Goose. `scripts/regen_bindings.sh`, which CI
runs, checks the fixed point: the bindings build a plugin that writes those same
bindings.

A change to what the generator emits goes in two steps, as the plugin that has the
change is built from bindings without it. `scripts/regen_bindings.sh --update` writes
them, and running it again must report no change.

## What was weighed

- **Committed bindings** add 10,000 generated lines that nobody reads, and a clean
  checkout needs nothing but Goose.
- **A released plugin binary to bootstrap from** adds no lines, but needs a download
  for every platform and a release for every change. The owner handles releases, and
  there are none yet.
- **Bindings written by hand** would be a second implementation of what the generator
  already writes, which is what this removes.

## What replaced the Zig generator as a check

`scripts/selfhost_diff.sh` compared the two generators byte for byte, and last found
them identical in 137 cases. What it stood for is now:

- the goldens and `wkt/`, unchanged by the removal, for what is generated;
- `tests/selfhost/*_unit.goose`, which port all 34 Zig unit tests, for what is rejected
  and how names resolve;
- `scripts/regen_bindings.sh`, for the plugin's own bindings.

A bug the two generators shared stays a bug, and no second implementation will notice
a new one. The conformance suite and the interop tests are what check generated code
against other implementations.
