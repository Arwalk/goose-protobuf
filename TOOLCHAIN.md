# Toolchain pins

Checked 2026-11-03. Change a pin only in a dedicated commit that also updates
CI and, if needed, the golden files and the conformance failure list.

| Tool | Pin | Commit | Why |
|---|---|---|---|
| Zig | 0.17.1 | - | zig-protobuf v6.0.1 needs `minimum_zig_version = "0.17.0"` |
| zig-protobuf | v6.0.1 | `b407c70b3a98` | Latest tag. Pinned by archive URL and hash in `generator/build.zig.zon`. Its own manifest says `version = "7.0.0"` |
| protobuf / protoc | v36.2 | `2c74169b3406` | The protoc that zig-protobuf v6.0.1 downloads, and the version its conformance runs use. Submodule `third_party/protobuf` |
| Goose | v2026.3 | `8511ae34bdc9` | Latest release. `goose version` prints `goose runtime 4d3da949e563`, not the tag |
| beads (`bd`) | 1.3.2 | - | The version that created `.beads/` |

## Installing

`scripts/install_toolchain.sh [prefix]` installs the pinned protoc and Goose
into `prefix` (default `.tools/`, which is gitignored), on linux-x64,
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
types' `.proto` files, which `scripts/wkt.sh` generates `wkt/` from. A pin change updates the version and all three sha256 sums in the
script, and reruns `scripts/edition_defaults.sh --update`.

## Notes

- **zig-protobuf** exports only the `protobuf` module. The `descriptor.proto` /
  `plugin.proto` bindings are in its `bootstrapped-generator/google/` and
  import each other through `../`, so they can't be wrapped as modules as-is.
  `generator/build.zig` copies both files into one tree with a `WriteFiles`
  step, under a root file `pb_plugin.zig`, and builds the `pb_plugin` module
  from it. The bindings therefore stay pinned to the zig-protobuf hash, with
  no vendored copy and no protoc run at build time.
- zig-protobuf's `build.zig` always resolves its lazy `protoc` 36.2
  dependency, so the first `zig build` downloads protoc.
- Zig's HTTP client can fail behind an HTTP proxy (`HttpConnectionClosing`).
  The workaround is to download the archive with curl and run
  `zig fetch <file>`, which fills the cache under the same hash.
- **protobuf v36.2** has no git submodules. CMake fetches abseil-cpp and
  jsoncpp (FetchContent) when it builds the conformance runner, so that
  build needs network.

## Conformance runner prerequisites

`scripts/build_runner.sh` needs:

- CMake 3.16 or later (tested with 4.2.3), a C++17 compiler (gcc or clang),
  and git, which FetchContent uses.
- Ninja (optional), used when it is on `PATH`.
- Network access to github.com on the first configure, for abseil-cpp
  20250512.1 and jsoncpp 1.9.6.

Install them with `apt-get install cmake ninja-build g++ git` on Ubuntu, or
`brew install cmake ninja` on macOS (with the Xcode command line tools).

If `.tools/bin/protoc` is the pinned 36.2, the script passes it as
`WITH_PROTOC`, so the build skips protoc, libprotoc and upb. Otherwise it
builds protoc from source. On a 16-core Linux box, the first build takes
about 1.5 min with the pinned protoc and 2.3 min without it. Later runs skip
configure and only rebuild what changed (under 1 s when nothing did). The
runner ends up at `build/pb/conformance_test_runner`. The script prints that
path on stdout and sends the build log to stderr. To reconfigure, delete
`build/pb`. The macOS build is untested locally, and CI checks it
(gpb-iip.9).
- **Goose release assets**: `goose-v2026.3-{linux-x64,macos-arm64,macos-x64}.tar.gz`
  and `goose-v2026.3-windows-x64.zip`. On macOS, run `xattr -dr com.apple.quarantine`
  on the unpacked directory. On Linux, glibc 2.35 or later with `libc6-dev`.
  A C compiler (gcc/clang) is needed for `goose build`.
- Goose has **no formatter and no `goose test`**. Generated code is checked
  with `goose check`, and the generator's output must be byte-deterministic.
- The conformance suite does not support Windows, so CI runs on Linux and
  macOS only.
