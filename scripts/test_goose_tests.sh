#!/usr/bin/env bash
# Self-test for scripts/goose_tests.sh on scripts/testdata/goose_tests/:
# the pass_ fixture passes, every fail_ fixture fails, the run exits 1.
# Usage: scripts/test_goose_tests.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
data="$root/scripts/testdata/goose_tests"
out="$("$root/scripts/goose_tests.sh" "$data" 2>&1)"; status=$?
bad=0
[ $status -eq 1 ] || { echo "FAIL want exit 1, got $status"; bad=1; }
for f in "$data"/*_test.goose; do
  rel="${f#$root/}"; want=FAIL
  case "$(basename "$f")" in pass_*) want=PASS ;; esac
  if grep -q "^$want $rel" <<<"$out"; then echo "PASS $rel reported $want"
  else echo "FAIL $rel not reported $want"; bad=1; fi
done
[ $bad = 0 ] || echo "$out"
exit $bad
