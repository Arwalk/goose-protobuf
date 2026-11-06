#!/usr/bin/env bash
# Generates protos with the plugin and `goose check`s every output file,
# failing on errors and on warnings. For protos outside tests/protos that
# have no golden, such as the conformance messages.
# Usage: scripts/check_generated.sh [-I dir]... file.proto...
# Example:
#   scripts/check_generated.sh -I third_party/protobuf/src \
#     google/protobuf/test_messages_proto3.proto
# What the protos import is generated and checked too. Imports resolve from
# the root file's directory, so each output file is checked through a small
# root file at the output root, next to a copy of the pb_wire package.
# Env: PLUGIN (default: scripts/build_plugin.sh), PROTOC, GOOSE
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"

includes=(); protos=()
while [ $# -gt 0 ]; do
  case "$1" in
    -I) includes+=(-I "$2"); shift 2 ;;
    -I*) includes+=("$1"); shift ;;
    *) protos+=("$1"); shift ;;
  esac
done
[ ${#protos[@]} -gt 0 ] || { echo "usage: $0 [-I dir]... file.proto..." >&2; exit 2; }
wkt="$(ls -d "$root"/.tools/protoc-*/include 2>/dev/null | head -1)"
[ -n "$wkt" ] && includes+=(-I "$wkt")

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  PLUGIN="$root/build/protoc-gen-goose"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
closure=()
while IFS= read -r i; do closure+=("$i"); done \
  < <("$root/scripts/proto_closure.sh" "${includes[@]}" "${protos[@]}")
[ ${#closure[@]} -gt 0 ] || { echo "FAIL protoc"; exit 1; }
"$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$tmp" \
  "${includes[@]}" "${closure[@]}" || { echo "FAIL protoc"; exit 1; }
"$root/scripts/vendor_runtime.sh" "$tmp"

bad=0; n=0
while IFS= read -r f; do
  n=$((n + 1))
  rel="${f#$tmp/}"
  mod="${rel%.goose}"
  echo "import ${mod//\//.};" > "$tmp/check_root.goose"
  if ! (cd "$tmp" && "$goose" check check_root.goose) >"$tmp/log" 2>&1; then
    echo "FAIL $rel: goose check failed"
    grep -v '^parsed ok\|^typechecked ok\|^bce:' "$tmp/log" | sed 's/^/    /'
    bad=1
  elif grep -q 'warning:' "$tmp/log"; then
    echo "FAIL $rel: goose check warned"
    grep 'warning:' "$tmp/log" | sed 's/^/    /'
    bad=1
  else
    echo "ok   $rel"
  fi
done < <(find "$tmp" -name '*.goose' -type f ! -name pb_wire.goose ! -name check_root.goose ! -path "$tmp/pb_wire/*" | LC_ALL=C sort)
[ $n -gt 0 ] || { echo "FAIL no files generated"; exit 1; }
exit $bad
