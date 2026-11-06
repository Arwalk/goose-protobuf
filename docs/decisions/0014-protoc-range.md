# 0014: which protoc versions are supported

- Status: proposed for the project owner. The range is measured and in the docs. How
  it changes decision 0012's rule on raised pins needs the owner's review.
- Date: 2026-11-06
- Bead: gpb-ky7.8
- Toolchain: Goose v2026.3, linux-x64
- Evidence: `scripts/protoc_versions.sh`, which CI runs
- Builds on: [0012](0012-public-api.md)

## Question

The docs asked for protoc 36.2 exactly, which is a large ask of a team or distribution
that has another. Which releases work, and what does the project promise about them?

## Measured

Each release ran the golden, well-known type and round-trip tests, using its own
include directory:

| protoc | Result |
|---|---|
| 25.9, 26.1 | Everything passes except `editions`, `editions_file` and `editions_smoke`: protoc refuses editions without `--experimental_editions` |
| 27.0, 27.5, 28.3, 29.6, 30.2, 31.1, 32.1, 33.6, 34.2, 35.1, 36.2 | Everything passes, and the generated code is byte-identical to the goldens |

## Decision

**The supported range is protoc 27.0 up to the pinned version.** 27.0 is the first
release that takes editions without a flag, and CI runs the first release of the range,
the last release of each major and the pin. Linux only: the plugin sees the same bytes
on every platform.

Older releases are not supported, although proto2 and proto3 happen to work on the two
measured. Newer ones are untested until the pin moves.

Only the pin runs the rest: conformance, interop and the plugin's own bindings.
Generating with another release gives the same bytes, so those results carry over, and
the goldens are what would notice if that stopped being true.

## What this does to decision 0012

Decision 0012 makes a raised tool pin a major, as it can force users to upgrade. This
record proposes that for protoc, the range changes which change does that:

- **Raising the pin widens the range.** Nobody has to upgrade, so it is not breaking,
  and takes a minor if it adds a capability such as a new edition.
- **Raising the floor, 27.0, is what forces an upgrade**, so that is the major.

Goose has no range: the plugin and the generated code are Goose programs, and one
version is tested. A raised Goose pin stays a major.

## Rejected

- **Just documenting the range**, with no CI: nothing would notice a protoc release
  changing what the plugin receives. It adds five minutes in a job of its own.
- **Testing every patch release**: more time in CI for little more cover, as the first
  and last release of 27 gave the same result.
- **Supporting 25 and 26 with editions left out**: a second kind of support to explain.
