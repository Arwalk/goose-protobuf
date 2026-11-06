#!/usr/bin/env bash
# A pool past 2^32 elements ends the program, where a position would otherwise wrap and
# a decoder would return wrong data. It touches 4 GiB of memory, so this runs once a
# week in CI and not on every push.
# Usage: scripts/test_pool_limit.sh
# Env: GOOSE (default goose; .tools/bin first)
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
goose="${GOOSE:-goose}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cp "$root/tests/pool_limit/pool_limit.goose" "$tmp/"
"$root/scripts/vendor_runtime.sh" "$tmp"
if ! (cd "$tmp" && "$goose" build pool_limit.goose --stack-reserve 16G -o pool_limit) >"$tmp/log" 2>&1; then
  echo "FAIL it does not build"; cat "$tmp/log"; exit 1
fi
"$tmp/pool_limit" >"$tmp/out" 2>&1; status=$?
if [ "$status" -eq 0 ]; then
  echo "FAIL a pool past 2^32 elements went on: $(cat "$tmp/out")"; exit 1
fi
if ! grep -q 'a pool holds over 2^32 elements' "$tmp/out"; then
  echo "FAIL it ended, but not on the check (exit $status): $(cat "$tmp/out")"; exit 1
fi
echo "PASS a pool past 2^32 elements ends the program: $(cat "$tmp/out")"
