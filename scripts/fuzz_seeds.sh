#!/usr/bin/env bash
# Refresh tests/fuzz/seeds.tar.gz, scripts/fuzz.sh's committed seeds: every binary
# input of the conformance suite, cut down by libFuzzer to those that add
# coverage. Rerun it by hand when the conformance suite or the pin changes.
# Usage: scripts/fuzz_seeds.sh
# Needs: scripts/build_runner.sh, and a build/fuzz/fuzz from scripts/fuzz.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
[ -x "$root/build/fuzz/fuzz" ] || { echo "error: no build/fuzz/fuzz; run scripts/fuzz.sh 1" >&2; exit 1; }
"$root/scripts/build_testee.sh" "$root/build/testee"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/raw" "$tmp/merged"
"$protoc" --include_imports --descriptor_set_out="$tmp/desc" \
  -I "$root/third_party/protobuf" conformance/conformance.proto
cat >"$tmp/testee" <<SH
#!/bin/sh
PYTHONPATH="$root/.tools/python" FUZZ_RECORD_DIR="$tmp/raw" FUZZ_RECORD_DESC="$tmp/desc" \
  exec python3 "$root/tests/fuzz/record_testee.py" "$root/build/testee"
SH
chmod +x "$tmp/testee"
"$root/scripts/run_conformance.sh" "$tmp/testee" --maximum_edition 2023 >"$tmp/log" 2>&1 ||
  { tail -20 "$tmp/log"; exit 1; }
tail -1 "$tmp/log"
echo "recorded $(find "$tmp/raw" -type f | wc -l) inputs"
"$root/build/fuzz/fuzz" -merge=1 "$tmp/merged" "$tmp/raw" 2>&1 | tail -1
# One file, not a thousand: the repository is what package users fetch (decision 0005).
(cd "$tmp/merged" && ls | LC_ALL=C sort |
  tar --owner=0 --group=0 --numeric-owner --mtime=@0 -T - -cf -) | gzip -9n >"$root/tests/fuzz/seeds.tar.gz"
echo "seeds: $(find "$tmp/merged" -type f | wc -l)"
