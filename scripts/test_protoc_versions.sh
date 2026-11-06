#!/usr/bin/env bash
# Self-test for scripts/protoc_versions.sh, on the pinned protoc so nothing is
# downloaded: it passes as things are, and fails on a golden that differs, a round trip
# that fails, and a version with no recorded checksum.
# Usage: scripts/test_protoc_versions.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pin="$(protoc --version | cut -d' ' -f2)"

"$root/scripts/build_plugin.sh" >/dev/null || exit 1
export PLUGIN="$root/build/protoc-gen-goose"

# One small round trip, so that each run is short.
mkdir -p "$tmp/rt" && cp -R "$root/tests/roundtrip/scalars" "$tmp/rt/"
export ROUNDTRIP_DIR="$tmp/rt"

bad=0
run() {  # run <want: 0|nonzero> <grep-pattern> <description> <version>
  "$root/scripts/protoc_versions.sh" "$4" >"$tmp/log" 2>&1
  local got=$? ok=1
  if [ "$1" = 0 ]; then [ $got -eq 0 ] || ok=0; else [ $got -ne 0 ] || ok=0; fi
  grep -q -e "$2" "$tmp/log" || ok=0
  if [ $ok = 1 ]; then echo "PASS $3"
  else echo "FAIL $3 (exit $got, want $1, pattern '$2')"; cat "$tmp/log"; bad=1; fi
}

run 0 "^PASS protoc $pin\$" "the pinned protoc passes" "$pin"

cp -R "$root/tests/golden" "$tmp/golden"
echo "// changed" >> "$tmp/golden/scalars/scalars.goose"
GOLDEN_DIR="$tmp/golden" run nonzero "^FAIL protoc $pin: golden\$" "a changed golden fails" "$pin"

for f in "$tmp"/rt/scalars/*_roundtrip.goose; do echo 'fn main() { abort("broken"); }' > "$f"; done
run nonzero "^FAIL protoc $pin: roundtrip\$" "a failing round trip fails" "$pin"

run nonzero "no checksum recorded for protoc 1.2.3" "a version with no checksum fails" 1.2.3
exit $bad
