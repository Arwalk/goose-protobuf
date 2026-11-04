#!/usr/bin/env bash
# Self-test for scripts/fuzz.sh: a target that aborts on some input must make it
# exit nonzero, and leave that input in a crash file. Goose ends a failure with
# _Exit, so without tests/fuzz/fuzz_entry.c's redirect none would be left.
# Usage: scripts/test_fuzz.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export FUZZ_OUT="$tmp/out" FUZZ_TARGET="$root/scripts/testdata/fuzz/abort_target.goose"
log="$("$root/scripts/fuzz.sh" 60 2>&1)"; status=$?
bad=0
if [ $status -ne 0 ]; then echo "PASS a failing target exits nonzero"
else echo "FAIL a failing target exited 0"; bad=1; fi
if grep -q 'found it' <<<"$log"; then echo "PASS the message is printed"
else echo "FAIL no message"; bad=1; fi
crash="$(ls "$FUZZ_OUT"/crash-* 2>/dev/null | head -1)"
if [ -n "$crash" ] && [ "$(od -An -tx1 -N1 "$crash" | tr -d ' ')" = 7f ]; then
  echo "PASS the input is saved"
else echo "FAIL no crash file holding the input"; bad=1; fi
[ $bad = 0 ] || echo "$log" | tail -20
exit $bad
