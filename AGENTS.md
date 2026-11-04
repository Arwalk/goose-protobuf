# Agent Instructions: goose-protobuf

`protoc-gen-goose` is a Zig protoc plugin. It generates Goose code for the
protobuf **binary wire format only**, and the conformance suite is the
measure of correctness. Read README.md for scope and layout, and TOOLCHAIN.md
for the pinned versions and their caveats.

## Build & test

```bash
(cd generator && zig build && zig build test)   # generator (Zig 0.17.1)
goose check runtime/pb_wire.goose               # Goose typecheck
scripts/build_runner.sh                         # conformance_test_runner
scripts/run_conformance.sh [testee] [flags]     # conformance suite
scripts/golden.sh                               # golden tests (--update to accept)
scripts/goose_tests.sh [paths]                  # Goose unit tests (tests/**/*_test.goose)
scripts/roundtrip.sh [names]                    # round-trip tests (tests/roundtrip/<name>/)
scripts/interop.sh [names]                      # the same cases through Goose, protoc and Python
scripts/fuzz.sh [seconds]                       # libFuzzer on generated decoders (needs clang)
scripts/check_generated.sh [-I dir] protos      # generate + goose check, no golden
scripts/wkt.sh                                  # wkt/ matches the plugin (--update to accept)
scripts/edition_defaults.sh                     # feature defaults match protoc (--update to accept)
scripts/bench_maps.sh [sizes]                   # map decode timings (decision 0008)
```

Golden tests: each `tests/protos/<name>.proto` is generated twice (the two
outputs must be byte-identical), diffed against `tests/golden/<name>/` (no
directory means no files), and every golden `.goose` file goes through
`goose check` next to a copy of `runtime/pb_wire.goose` and the generated
files it imports. After an
intended generator change, run `scripts/golden.sh --update` and review the
golden diff in the commit, and the same with `scripts/wkt.sh --update` for the
well-known types in `wkt/`. `scripts/test_golden.sh`,
`scripts/test_goose_tests.sh`, `scripts/test_roundtrip.sh`, `scripts/test_interop.sh`, `scripts/test_fuzz.sh`,
`scripts/test_check_generated.sh` and `scripts/test_run_conformance.sh`
self-test the harnesses.

Goose unit tests: a `*_test.goose` file under `tests/` is a program built
with `--debug` and run; it passes iff it exits 0 (fail with `abort(...)`).
Import the runtime as a directory package, since a plain `import` cannot
reach above the test's directory: `import pb_wire from "../../runtime";`.

Round-trip tests: `tests/roundtrip/<name>/` holds `<case>.txtpb` files,
each with a `# proto-message: pkg.Msg` line, and a
`<name>_roundtrip.goose` program. The harness generates
`tests/protos/<name>.proto` and the files it imports next to them, encodes each case with
`protoc --encode` into `<case>.bin`, which the program embeds with
`embed_file`, then builds and runs the program; it passes iff it exits 0.

Interop tests: `scripts/interop.sh` needs no program. It runs every round-trip
`.txtpb` through a generated echo (decode, encode), checking what comes out with
`protoc --decode` and Python protobuf, and what those encode back through the echo.
Goose's bytes must equal Python's deterministic ones, so a case whose message
Goose only partly knows says `# interop-decode-as: pkg.Msg`. A mismatch prints a
hex diff.

## Conventions

- **Commits**: Conventional Commits. The subject is 50 characters or fewer,
  capitalised after the type, imperative, with no trailing period, e.g.
  `feat: Emit packed repeated fields`. Wrap the body at 72 columns; it
  explains what changed and why.
- **Bug fixes are test-first**: write the failing test, run it and watch it
  fail, then fix.
- **Generated code must pass `goose check`.** Goose has no formatter, so
  generator output must be byte-deterministic (same input, same bytes), and
  golden tests check that.
- **The conformance failure list may only shrink.** Never add an entry to
  `conformance/failure_list_goose.txt` to make CI pass. A newly failing test
  is a bug.
- **Track all work in beads** (`bd`). Don't write markdown TODO lists or TODO
  comments without a bead id. Spike conclusions go in `docs/decisions/` as
  `NNNN-short-title.md`.
- **Goose pitfalls**: Goose `varint` is not the protobuf varint. Do zigzag
  and varint maths in `u64`, and use `as!` for wrapping casts (`as` aborts
  under `--debug`). `T?` is a nullable reference, so field presence uses
  has-bits. Enums have no discriminants, so protobuf enums are `i32`
  constants.
- **Pins**: toolchain versions change only in a dedicated commit that updates
  TOOLCHAIN.md, CI, and any affected goldens and failure list.

## Beads workflow

```bash
bd ready                      # unblocked work, highest priority first
bd show <id>                  # read the acceptance criteria before starting
bd update <id> --claim        # claim
bd create "..." -t task -p 2 -l generator --parent <epic> \
  --acceptance "..." --deps blocked-by:<id>   # new work found along the way
bd close <id> --reason "..."  # only once the acceptance criteria are met
```

Each phase is an epic, and each task carries labels from `generator`,
`runtime`, `conformance`, `ci`, `spike` and `docs`. There is no git remote
yet, so the Dolt database is local only. `.beads/issues.jsonl`, the
committed export, is the git-tracked copy.

**The project owner handles the remote, pushes, tags and releases.** Agents
do not add a remote, push, tag or ask about them. The repository will be on
GitHub, so CI is GitHub Actions (`.github/workflows/ci.yml`), which cannot run
until the owner pushes.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
