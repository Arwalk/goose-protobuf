# Install

What you need to generate Goose code from `.proto` files and to build it.

## Requirements

| Tool | Version | Why |
|---|---|---|
| Goose | v2026.3 | Builds your program and the plugin |
| `protoc` | 27.0 to 36.2 | Runs the plugin on your `.proto` files |
| C compiler (gcc or clang) | any | `goose build` uses it |

Each release is tested with these versions, and other versions may not work. The
script below installs protoc 36.2, but one you already have is fine if it is in this
range.

On Linux, Goose needs glibc 2.35 or later and `libc6-dev`.

| Platform | Status |
|---|---|
| Linux x64 | Tested |
| macOS arm64 | Tested by CI |
| macOS x64 | The tools install, but CI does not run on it |
| Windows x64 | Goose has a release (`goose-v2026.3-windows-x64.zip`), but this project is not yet tested on it, and the scripts below need a Unix shell |

## Install Goose and protoc

If you do not have them, clone this repository and let it fetch both, checked against
their recorded checksums. Your project goes next to the clone, as `../goose-protobuf`.
From your project's directory:

```sh run
../goose-protobuf/scripts/install_toolchain.sh
export PATH="$PWD/../goose-protobuf/.tools/bin:$PATH"
goose version
protoc --version
```

prints, at the end:

```text output
goose runtime 4d3da949e563
libprotoc 36.2
```

This installs into the clone's `.tools/`. To put them elsewhere, give the script a
prefix: `install_toolchain.sh /opt/goose-tools`. `goose version` prints its runtime's
commit, not the release's tag.

To install Goose yourself, its
[release](https://github.com/aardappel/goose/releases/tag/v2026.3) has
`goose-v2026.3-linux-x64.tar.gz`, `goose-v2026.3-macos-arm64.tar.gz` and
`goose-v2026.3-macos-x64.tar.gz`. On macOS, run `xattr -dr com.apple.quarantine` on
the unpacked directory.

## Install the plugin

```sh run
../goose-protobuf/scripts/install_plugin.sh
```

This builds `protoc-gen-goose` and copies it to `~/.local/bin`. The copy stands alone,
needing neither the clone nor Goose to run. If the script tells you the directory is
not on your `PATH`, add it, as `protoc` finds the plugin there. To put it elsewhere,
give a prefix: `install_plugin.sh /usr/local` writes `/usr/local/bin/protoc-gen-goose`.

`protoc-gen-goose --version` says which version you have. Check that `protoc` finds it:

```sh run
printf 'syntax = "proto3";\nmessage M {}\n' > m.proto
protoc --goose_out=. m.proto
ls m.goose
```

```text output
m.goose
```

To update, pull the clone and run the script again.

## Get the runtime

Generated code imports a small package, `pb_wire`, and your program's root file says
where it comes from. Use the same version as the plugin, as your program will not
build otherwise.

| Source | Root file line | Use it when |
|---|---|---|
| A checkout | `import pb_wire from "../goose-protobuf";` | You are starting out |
| A git source | `import pb_wire from "owner/repo@vX.Y.Z";` | You want Goose to fetch it. Pin a commit if the build must be reproducible, since a tag can move |
| A copy | `import pb_wire;` | You want no network and no other directory. `scripts/vendor_runtime.sh <dir>` makes the copy, next to your root file |

[The quickstart](quickstart.md) tries them on a small program.
