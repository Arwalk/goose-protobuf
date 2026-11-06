# Decisions

Why the project is the way it is. Each record answers one question, as it stood on its
date. A record is not rewritten when it stops holding: what no longer holds is marked
in place, starting `(Since superseded:`, and the current fact lives where
[the documentation map](../README.md) says. To use the project, read the guides, not
these.

**Status:** *accepted* holds today, *accepted, amended* holds with a later record's
change, and *proposed* is waiting for the project owner's review.

| Record | What it decided | Status |
|---|---|---|
| [0001](0001-message-layout.md) | Messages live in global pools, reached by handles, as Goose has no heap | Accepted, amended by 0008 on repeated map keys |
| [0002](0002-float-bits.md) | Floats convert to and from bits in pure Goose, with no C | Accepted |
| [0003](0003-stdio.md) | Exact-length stdin reads and stdout flushes, for the conformance testee | Accepted |
| [0004](0004-decode-errors.md) | Decode errors are a sticky code in the reader, with no abort | Accepted |
| [0005](0005-runtime-distribution.md) | Generated code imports `pb_wire` by bare name, and this repository is the package | Accepted, and its release procedure moved to [RELEASING.md](../../RELEASING.md) |
| [0006](0006-naming.md) | How `.proto` names become Goose names | Accepted |
| [0007](0007-well-known-types.md) | Well-known types are generated, committed and ship in the `pb_wire` package | Accepted |
| [0008](0008-map-decode.md) | Decoding a map folds repeated keys once, after the input | Accepted |
| [0009](0009-extension-utf8.md) | The UTF-8 of a string extension is not validated | Accepted |
| [0010](0010-no-map-index.md) | Maps have no index, and get a bulk append | Accepted, until a workload needs one |
| [0011](0011-goose-only-generator.md) | The generator is written in Goose, on bindings it commits | Accepted |
| [0012](0012-public-api.md) | What is public, and how versions move | Accepted, with the rules for users in [docs/versions.md](../versions.md) |
| [0013](0013-generated-code-outside-the-root.md) | A directory of generated code is a package, so the plugin needs no parameter | Proposed |
| [0014](0014-protoc-range.md) | protoc 27.0 up to the pin is supported, and what that does to decision 0012 | Proposed |
| [0015](0015-package-fetch-size.md) | What a git source costs a consumer, and that nothing needs trimming | Accepted |
