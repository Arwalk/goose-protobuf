#!/usr/bin/env bash
# Measures map decode time against input size (gpb-dx9.7), each run in a process
# of its own. Prints: shape entries input_bytes unique_entries decode_seconds.
# A run past the timeout prints TIMEOUT instead of its figures.
# Usage: scripts/bench_maps.sh [sizes...]   (default 10000 40000 160000 1000000)
# Env: SHAPES  (default: all of them)
#      BENCH_TIMEOUT seconds per run (default 600)
#      PLUGIN, PROTOC, GOOSE (default: scripts/build_plugin.sh; protoc, goose; .tools/bin first)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
limit="${BENCH_TIMEOUT:-600}"
shapes="${SHAPES:-int_random str_random str_prefix int_dup int_half small_maps}"
[ $# -gt 0 ] || set -- 10000 40000 160000 1000000

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  PLUGIN="$root/build/protoc-gen-goose"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$root"/tests/bench/maps/* "$tmp"/
"$root/scripts/vendor_runtime.sh" "$tmp"
"$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$tmp" \
  -I "$tmp" bench_maps.proto || exit 1
(cd "$tmp" && "$goose" build run_bench.goose -o "$tmp/bench") >/dev/null 2>"$tmp/build.log" ||
  { cat "$tmp/build.log" >&2; exit 1; }
# Generated and built: from here on the run no longer reads the plugin.
echo "# built" >&2

for shape in $shapes; do
  for n in "$@"; do
    timeout "$limit" "$tmp/bench" "$shape" "$n" || echo "$shape $n TIMEOUT >${limit}s"
  done
done
