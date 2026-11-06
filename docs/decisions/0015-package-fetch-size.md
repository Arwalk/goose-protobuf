# 0015: what a git source costs a consumer

- Status: accepted. Nothing needs trimming, and the consumer test holds that.
- Date: 2026-11-06
- Bead: gpb-ky7.9
- Toolchain: Goose v2026.3, linux-x64
- Evidence: `scripts/consumer_test.sh`
- Builds on: [0005](0005-runtime-distribution.md)

## Question

A git source clones this repository, with `tests/`, `conformance/` and the agent
directories. Goose's documentation says every `.goose` file under a package root counts
as the package's, while decision 0005 measured that unimported files are not compiled.
What does this cost a consumer, and should it be trimmed?

## Measured

Goose runs `git clone --depth 1 --branch <ref> --recurse-submodules
--shallow-submodules`, here from a `file://` repository, as the agent that measured
this could not read the GitHub one. The size of what travels is the same; the time on a
real network was not measured.

| | Full clone | Without everything the package does not import |
|---|---|---|
| On disk, with `.git` | 5.3 MB | 964 KB |
| `.git`, about what travels | 764 KB | |
| `goose check` of a small program (median of 9) | 17 ms | 17 ms |
| `goose run` of it (median of 9) | 36 ms | 37 ms |

`tests/` is 2.9 MB of that, and the agent directories about 100 KB. The 132 `.goose`
files make no difference to the compiler: a file with a syntax error and an unresolvable
`extern fn` under `tests/` broke neither `goose run` nor `goose build`.

The documentation's "counts as the package's" is about one thing: which files the JIT
symbol table searches for `extern fn`, for a package with a native part. This package
has none, so the sidecar's `exclude` would do nothing.

## Decision

**Trim nothing.** A consumer pays about 5 MB of cache, once per version, and no compile
time. Git has no way to leave files out of a clone, so trimming would mean a separate
repository, which decision 0005 rejected for better reasons than these.

The consumer test holds both results: a broken file planted under `tests/` must not
affect a build, and a fetched package over 20 MB fails.
