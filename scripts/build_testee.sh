#!/usr/bin/env bash
# Build the conformance testee from generated bindings.
# Usage: scripts/build_testee.sh [out]   (default build/testee)
#
#   1. build the plugin (zig build);
#   2. generate google/protobuf/test_messages_proto3.proto from the
#      protobuf submodule (third_party/protobuf/src) with it;
#   3. stage the generated file, conformance/testee.goose, io.c,
#      testee.build and runtime/pb_wire.goose in one flat directory,
#      build/testee-src/ (flat, so every file imports the same pb_wire);
#   4. goose build it to <out>.
# Env: PROTOC, GOOSE (default protoc, goose; .tools/bin first),
#      GOOSE_FLAGS (extra goose build flags, e.g. --debug)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
out="${1:-$root/build/testee}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
src="$root/third_party/protobuf/src"
stage="$root/build/testee-src"

die() { echo "error: $*" >&2; exit 1; }
[ -f "$src/google/protobuf/test_messages_proto3.proto" ] ||
  die "no $src/google/protobuf/test_messages_proto3.proto; git submodule update --init"
command -v "$goose" >/dev/null || die "goose not found; see TOOLCHAIN.md"

(cd "$root/generator" && zig build) || die "zig build failed"
plugin="$root/generator/zig-out/bin/protoc-gen-goose"

rm -rf "$stage"; mkdir -p "$stage/gen"
"$protoc" --plugin=protoc-gen-goose="$plugin" --goose_out="$stage/gen" \
  -I "$src" google/protobuf/test_messages_proto3.proto
mv "$stage/gen/google/protobuf/test_messages_proto3.goose" "$stage/"
rm -rf "$stage/gen"
cp "$root"/conformance/testee.goose "$root"/conformance/io.c \
   "$root"/conformance/testee.build "$root"/runtime/pb_wire.goose "$stage/"

mkdir -p "$(dirname "$out")"
# shellcheck disable=SC2086
(cd "$stage" && "$goose" build testee.goose ${GOOSE_FLAGS:-} -o "$out") >&2
