# 0007: well-known types ship in the pb_wire package

- Status: accepted by the project owner, who reversed the first answer here
  ("each user generates them").
- Date: 2026-11-04
- Beads: gpb-8qn.5 (first answer), gpb-dx9.6 (this one)
- Builds on: [0005](0005-runtime-distribution.md) (distribution),
  [0006](0006-naming.md) (naming)

## Question

Protobuf's well-known types need Goose bindings. Do those ship with the
runtime, or does each user generate them?

## Decision

**They are generated once, committed in `wkt/`, and part of the `pb_wire`
package.** For seven files, those whose types have semantics of their own:
`any`, `duration`, `empty`, `field_mask`, `struct`, `timestamp`, `wrappers`.

A generated file with such a field writes `import pb_wire.wkt.duration;`, which
resolves in the package a program already declares, and still names the type
`google_protobuf::Duration`. So a program uses one in its root file with:

```goose
import pb_wire from "../goose-protobuf";
import pb_wire.wkt.duration;
```

The plugin writes nothing for those files when protoc names them, so tools that
pass a proto and its whole import closure keep working. A file is recognised
by its name and the package `google.protobuf`, so a user's own
`google/protobuf/any.proto` in another package is an ordinary proto. The other
files of `google/protobuf/` (`api`, `type`, `source_context`, `descriptor`) have
no special semantics, and stay ordinary too.

`scripts/wkt.sh --update` regenerates the tree, through the plugin parameter
`--goose_out=wkt:dir`; without `--update` it fails if `wkt/` is out of date,
and CI runs it. `struct.proto` becomes `wkt/struct_.goose`, as `struct` is a
Goose keyword (decision 0006). `tests/spikes/distribution/check.sh` builds a
consumer of a well-known type from a path, a git URL and a vendored copy.

## Why

- **Special semantics need one home.** These types have rules a `.proto` does
  not say: `Timestamp` and `Duration` are strings in JSON, wrappers are plain
  values, `Struct` is plain JSON, `Any` has to resolve its type URL. JSON is out
  of scope today, but it must not be closed off. Bindings each user generates
  could only get such rules from the generator, as text in every copy, or
  through hooks that every generated file had to call. A single copy in the
  package can have them beside it, in `wkt/`, and generated code that refers to
  that copy gets them.
- **It is what a comparable project landed on.** zig-protobuf's generator knows
  the full names of these types and re-exports `protobuf.wkt.X` in place of
  generating them, for the same set of files, with the JSON forms in
  `src/wkt.zig`.
- **The objections to shipping fell away.** The first answer rejected this for
  version skew and for needing a release step. Decision 0005 now publishes the
  runtime from this repository, so one tag names the generator, the runtime and
  `wkt/`, and they cannot differ within a checkout.
- **It still costs only what is used.** Each file is imported on its own, and
  Goose compiles only what a program imports.

## Generated, not hand-written

zig-protobuf writes its types by hand. Here the message code stays generated:
the layout is still moving (repeated, oneofs and maps change these files as
Phase 3 lands), and generated code cannot drift from the generator. Anything
special goes in a hand-written file beside the generated one, which is `DO NOT
EDIT`. Nothing of the kind exists yet, as no such rule is in scope. If a type
ever needs what a sibling file cannot do, the generator can leave that one out.

## Consequences

- A generator change usually means `scripts/wkt.sh --update` as well as
  `scripts/golden.sh --update`, with both diffs reviewed.
- `Struct`'s map and `Value`'s oneof are stored since gpb-gp4.4 and gpb-gp4.3,
  and `tests/roundtrip/wkt` round-trips them (gpb-gp4.6).
- A protoc pin change can change `wkt/`, like any golden.
- A program no longer chooses its copy of these types. One that wants other
  bindings for them cannot have them under the same files.
- Values have no helpers such as `Any` pack and unpack or time conversions yet.
  `wkt/` is now where they would go.

## Rejected

- **The user generates them** (the first answer): see above.
- **Hand-written bindings**, as zig-protobuf has: see above.
- **A second package**, `import wkt from "...";`: a git source cannot name a
  subdirectory (decision 0005), so it would need its own repository. Goose
  already loads a package's other modules as `import pb_wire.wkt.x;`.
- **`wkt/` under `runtime/`**: a git source's package root is the repository,
  and `runtime/` a path source's, so the import could not be the same for both.
  Reasoned from decision 0005, not built.
