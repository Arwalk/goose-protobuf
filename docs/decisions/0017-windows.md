# 0017: Windows is supported for the plugin and the runtime

- Status: accepted
- Date: 2026-11-06
- Bead: gpb-ky7.11
- Toolchain: Goose v2026.3 and protoc 36.2, windows-x64, under Wine 10.0 with clang 23
  from llvm-mingw

## Question

Goose has a Windows release, but nothing here had run on it. Do the plugin and the
runtime work there, and what would CI need?

## What was measured

The Windows releases of Goose and protoc run under Wine, and clang from llvm-mingw
gives `goose build` a compiler, so `goose build` made real Windows executables. The
project's bash scripts ran on Linux, calling those tools through small wrappers.

- **The plugin did not work.** On `syntax = "proto3"; message M { int32 a = 1; }`,
  protoc said `m.proto: not in proto_file`. Windows starts stdin in text mode: 11 bytes
  of `a\r\nb\x1ac\nd\xff\0e` read as 3, with the `\r` gone and input ended at `0x1A`.
- **`write_stdout` changed nothing** under Wine on a program built this way, but C
  defines stdout's start as text too, so the plugin sets both.
- **`read_file` and `write_file` kept every byte.**
- **`protoc --plugin=NAME=PATH` does not add `.exe`** to PATH, where a shell would.
- **`protoc --decode` ends its lines with CRLF**, which `proto_closure.sh` did not expect.

With these fixed, all 43 goldens came out byte-identical, and the 6 runtime unit tests
and 23 round trips passed.

## Decision

- The plugin's terminal check and binary stdio live in `generator-goose/plugin_stdio.c`,
  named by `main.build`, as an `extern` cannot differ by platform. The rule from
  [decision 0002](0002-float-bits.md) that `pb_wire` uses no C still holds, as this is the
  plugin's alone, and building it still needs only what any Goose program needs.
- `.gitattributes` makes every text file LF everywhere, since bash cannot run a CRLF
  script and goldens are compared by the byte.
- `install_toolchain.sh` takes Git Bash, with small scripts in place of its symlinks.
- CI's `windows` job runs the plugin build, runtime typecheck, goldens, unit tests and
  round trips. The other checks stay on Linux and macOS: they are the project's own
  tooling, and the conformance suite does not support Windows.

## What this did not measure

Wine is not Windows, and clang with mingw is not MSVC. The `windows` job is the first
thing to run on real Windows, with MSVC and Git Bash's path conversion. Until its
first run is seen, treat this record's numbers as Wine's. (Since then: the owner reported
the job green on real Windows on 2026-11-06.)
