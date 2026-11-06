# Toolchain pins

For people working on this repository: which version of each tool is pinned, why, and
how to change one. To use the plugin, see [docs/install.md](docs/install.md).

Checked 2026-11-03.

| Tool | Pin | Commit | Why |
|---|---|---|---|
| protobuf / protoc | v36.2 | `2c74169b3406` | Submodule `third_party/protobuf`. A pin change also regenerates the plugin's bindings: `scripts/regen_bindings.sh --update` |
| Python protobuf | 7.36.2 | - | The release of protobuf v36.2, for `scripts/interop.sh`. The pure-Python wheel, so one sha256 on every platform |
| Goose | v2026.3 | `8511ae34bdc9` | Latest release. `goose version` prints `goose runtime 4d3da949e563`, not the tag |
| clang | 21.1.8 | - | For `scripts/fuzz.sh` only, with `libclang-rt-dev` for libFuzzer and ASan. Ubuntu 26.04's package, so not installed by `scripts/install_toolchain.sh` or CI |
| buf | 1.75.0 | - | For `scripts/check_docs.py`, which runs `docs/build-systems.md`. Installed by `scripts/install_buf.sh`, not by `scripts/install_toolchain.sh`, as users do not need it |
| beads (`bd`) | 1.3.2 | - | The version that created `.beads/` |

## Changing a pin

Change a pin only in a dedicated commit that also updates CI and, if needed, the
golden files and the conformance failure list. That commit also:

- updates the version and every sha256 sum in `scripts/install_toolchain.sh`;
- reruns `scripts/edition_defaults.sh --update`;
- for a Goose pin, compares the keywords and builtins of its reference with
  `reference_names` in `tests/selfhost/names_unit.goose`;
- for a protoc pin, runs `scripts/regen_bindings.sh --update`, as the table says, and
  adds the new release to `scripts/protoc_versions.sh`
  ([decision 0014](docs/decisions/0014-protoc-range.md));
- updates the versions quoted in [docs/install.md](docs/install.md),
  [docs/usage.md](docs/usage.md) and the top entry of [CHANGELOG.md](CHANGELOG.md).
  `scripts/check_docs.py` runs the first, and fails on an old version.

## The pinned tools

`scripts/install_toolchain.sh [prefix]` installs the pinned protoc, Goose and
Python protobuf into `prefix` (default `.tools/`, which is gitignored), on linux-x64,
macos-arm64 and macos-x64. It checks each download against a sha256 recorded
in the script and aborts on a mismatch. It is idempotent: an
already-unpacked pin is skipped. Then put `.tools/bin` on `PATH`:

```sh
scripts/install_toolchain.sh
export PATH="$PWD/.tools/bin:$PATH"
goose version      # goose runtime 4d3da949e563
protoc --version   # libprotoc 36.2
```

`.tools/bin/goose` is a symlink into the unpacked release, and Goose finds
its stdlib through it. `.tools/protoc-36.2/include` holds the well-known
types' `.proto` files, which `scripts/wkt.sh` generates `wkt/` from.
`.tools/python` holds the unpacked protobuf wheel.

## Conformance runner prerequisites

`scripts/build_runner.sh` needs:

- CMake 3.16 or later (tested with 4.2.3), a C++17 compiler (gcc or clang),
  and git, which FetchContent uses.
- Ninja (optional), used when it is on `PATH`.
- Network access to github.com on the first configure, for abseil-cpp
  20250512.1 and jsoncpp 1.9.6. protobuf v36.2 has no git submodules, so CMake
  fetches them (FetchContent) when it builds the runner.

Install them with `apt-get install cmake ninja-build g++ git` on Ubuntu, or
`brew install cmake ninja` on macOS (with the Xcode command line tools).

If `.tools/bin/protoc` is the pinned 36.2, the script passes it as
`WITH_PROTOC`, so the build skips protoc, libprotoc and upb. Otherwise it
builds protoc from source. On a 16-core Linux box, the first build takes
about 1.5 min with the pinned protoc and 2.3 min without it. Later runs skip
configure and only rebuild what changed (under 1 s when nothing did). The
runner ends up at `build/pb/conformance_test_runner`. The script prints that
path on stdout and sends the build log to stderr. To reconfigure, delete
`build/pb`.

The macOS build is untested locally, and CI checks it. The conformance suite does
not support Windows, so CI runs on Linux and macOS only.
