# 0005: generated code imports pb_wire by bare name

- Status: accepted. The owner chose to publish from this repository
  (gpb-dx9.6), and that is done. It will be hosted on GitHub; the owner adds the
remote and makes the releases, when the project is ready (gpb-dx9.1).
- Date: 2026-11-04
- Bead: gpb-wof.5
- Toolchain: Goose v2026.3 (`goose runtime 4d3da949e563`), linux-x64
- Evidence: `tests/spikes/distribution/check.sh`, which builds a consumer for
  each case below with local git repositories and its own `GOOSE_HOME`. CI now
  checks the cases that matter to users with `scripts/consumer_test.sh`.

## Question

Generated files need `runtime/pb_wire.goose`. Goose packages are declared as
`import name from "source";`, only in a program's root file, and are a
directory holding `name.goose`, fetched from a path or a git repository. How
does generated code import the runtime, and what must this repository look
like for that to work?

## Decision

**The generator keeps emitting `import pb_wire;`.** It names no source, so one
generated file works however the program provides the runtime. The program
chooses, in its root file:

| The program | Root file line | Result |
|---|---|---|
| vendors a copy next to its root file | none | builds |
| uses a checkout | `import pb_wire from "../goose-protobuf";` | builds |
| uses a git repository | `import pb_wire from "owner/repo@v1.2.3";` | builds |

A vendored copy that needs well-known types also has `wkt/` at
`pb_wire/wkt/` (`scripts/vendor_runtime.sh`, decision 0007). `.../runtime` as
the path still builds a program that uses none.

This follows Goose's own rule, "only the root file declares packages": a
generated file writing a source would be a requirement every program had to
match, and would tie generated code to one host and version. The errors are
good enough to need no help from us. With no runtime the compiler says
`cannot find the module pb_wire`, and a vendored copy next to a declared
package says `pb_wire is both a file of this package ... and the declared
package`.

The generator therefore needs no option and no change, and neither do the
goldens: the hosting decision does not touch generated code. Imports between
generated files (decision 0006) resolve from the program's root as well, and a
generated tree may sit in a subdirectory if the imports match, which only a
future plugin option could arrange.

## What the repository layout must be

Measured, and not obvious from the documentation:

1. **A git source cannot name a subdirectory.** `repo.git/runtime@v1` fails to
   fetch, and Goose lists this as not built. A repository whose entry is only
   in `runtime/` fails with `has no pb_wire.goose`.
2. **A one-line entry fixes that.** A root `pb_wire.goose` holding
   `import .runtime.pb_wire;` makes this repository's layout a package.
   Other `.goose` files in the tree are not compiled unless imported, so the
   tests and goldens do no harm, even invalid ones.
3. **Goose clones with `--recurse-submodules`.** A consumer of this repository
   would also fetch `third_party/protobuf`, a 100 MB tree (shallow, but still
   that large), to get one 16 KB file. `update = none` for the submodule in
   `.gitmodules` keeps it out.

So publishing from this repository takes the entry file and `update = none`,
and **both are in place**. The second has a cost here: a plain
`git submodule update --init` skips the submodule, so the scripts, CI, the
README and the usage guide (`docs/usage.md`) say `--checkout`.

The rejected alternative was a separate repository holding only
`pb_wire.goose` at its root, which has no such costs but has to be kept in
step, and whose tags say nothing about the generator's version. Here the
generator, runtime and well-known types change together, and one tag names all
three.

## Release procedure

For the project owner, once there is a remote, for version `X.Y.Z`:

1. On `main`, with every gate green (the commands in AGENTS.md).
2. `git tag -a vX.Y.Z -m "vX.Y.Z"`, then push the tag.
3. Run `scripts/consumer_test.sh`, and build a consumer against the pushed tag
   in a clean `GOOSE_HOME`.
4. Users write `import pb_wire from "owner/repo@vX.Y.Z";` and build the plugin
   from the same tag.

A tag can move, so a build that must be reproducible pins a commit, as Goose's
documentation advises. Generated code and the runtime are only known to work
from the same version. There is no version check: a mismatch shows up as a
compile error on a missing `pb_` name when one was added or renamed, and not at
all when behaviour alone changed, so the usage guide (gpb-dx9.4) has to say to
keep them together.

## Rejected

- **A source in generated code**: see above.
- **A plugin option naming the source**: Goose reads such a line in a
  non-root file only as a requirement on the root, so it would add a second
  place to change versions and enable nothing.
- **Generated code embedding the runtime**: two generated files would declare
  it twice, and nothing would be shared.
- **A separate runtime repository**: see above.
- **Moving `runtime/pb_wire.goose` to the repository root**: it works, but the
  entry file does the same without moving anything, and the runtime is not
  what most of this repository is about.
