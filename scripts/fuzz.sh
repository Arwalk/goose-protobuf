#!/usr/bin/env bash
# Fuzz generated decoders with libFuzzer: decode, encode, decode, encode
# (tests/fuzz/fuzz_target.goose) over the conformance suite's test messages.
# Usage: scripts/fuzz.sh [seconds] [libFuzzer flags]   (default 60)
#
#   1. generate the messages and goose them to C (--debug, --standalone);
#   2. build it with clang -fsanitize=fuzzer,address, with tests/fuzz/fuzz_entry.c;
#   3. run it on build/fuzz/corpus, seeded from tests/fuzz/seeds.tar.gz
#      (scripts/fuzz_seeds.sh). A crash is left in build/fuzz/ and exits nonzero.
# Env: PROTOC, GOOSE (default protoc, goose; .tools/bin first),
#      CC_FUZZ (default clang; needs its compiler-rt fuzzer libraries),
#      FUZZ_REBUILD=0 keeps an existing fuzz binary,
#      FUZZ_TARGET another target program (default tests/fuzz/fuzz_target.goose),
#      FUZZ_OUT the output directory (default build/fuzz).
# The protobuf submodule must be checked out (git submodule update --init --checkout).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
cc="${CC_FUZZ:-clang}"
seconds=60
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then seconds="$1"; shift; fi
src="$root/third_party/protobuf/src"
out="${FUZZ_OUT:-$root/build/fuzz}"
stage="$out-src"
target="${FUZZ_TARGET:-$root/tests/fuzz/fuzz_target.goose}"
die() { echo "error: $*" >&2; exit 1; }
[ -f "$src/google/protobuf/test_messages_proto3.proto" ] ||
  die "no $src/google/protobuf/test_messages_proto3.proto; git submodule update --init --checkout"
command -v "$cc" >/dev/null || die "$cc not found; set CC_FUZZ"

mkdir -p "$out/corpus"
if [ "${FUZZ_REBUILD:-1}" != 0 ] || [ ! -x "$out/fuzz" ]; then
  (cd "$root/generator" && zig build) || die "zig build failed"
  rm -rf "$stage"; mkdir -p "$stage"
  closure=()
  while IFS= read -r i; do closure+=("$i"); done \
    < <("$root/scripts/proto_closure.sh" -I "$src" -I "$root/third_party/protobuf" \
          google/protobuf/test_messages_proto3.proto \
          google/protobuf/test_messages_proto2.proto \
          editions/golden/test_messages_proto3_editions.proto \
          editions/golden/test_messages_proto2_editions.proto \
          conformance/test_protos/test_messages_edition2023.proto | sort -u)
  "$protoc" --plugin=protoc-gen-goose="$root/generator/zig-out/bin/protoc-gen-goose" \
    --goose_out="$stage" -I "$src" -I "$root/third_party/protobuf" "${closure[@]}"
  cp "$target" "$stage/fuzz_target.goose"
  cp "$root/tests/fuzz/fuzz_entry.c" "$stage/"
  "$root/scripts/vendor_runtime.sh" "$stage"
  (cd "$stage" && "$goose" --standalone --debug --header fuzz.h -o fuzz.c fuzz_target.goose) >/dev/null
  # -O1: the generated file is large, and -O2 with ASan takes many minutes.
  "$cc" -g -O1 -w -fsanitize=fuzzer,address -D_Exit=fuzz_exit -I"$stage" \
    "$stage/fuzz.c" "$stage/fuzz_entry.c" -lm -o "$out/fuzz"
fi

rm -rf "$out/seeds"; mkdir "$out/seeds"
# Absent only on the way to scripts/fuzz_seeds.sh, which needs this build.
[ ! -f "$root/tests/fuzz/seeds.tar.gz" ] || tar -xzf "$root/tests/fuzz/seeds.tar.gz" -C "$out/seeds"
cd "$out"
exec ./fuzz -max_total_time="$seconds" -timeout=30 -rss_limit_mb=4096 \
  -artifact_prefix="$out/" "$@" corpus seeds
