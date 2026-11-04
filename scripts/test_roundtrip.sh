#!/usr/bin/env bash
# Self-test for scripts/roundtrip.sh on scripts/testdata/roundtrip/, with
# the real plugin: the `pass` and `imports` (uses a file its proto imports)
# cases pass; `abort` (the program aborts),
# `noheader` (a txtpb without '# proto-message:'), `noproto` (no proto)
# and `noprogram` (no *_roundtrip.goose) each fail; the run exits 1.
# Usage: scripts/test_roundtrip.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
data="$root/scripts/testdata/roundtrip"
out="$(PROTO_DIR="$data/protos" ROUNDTRIP_DIR="$data/cases" \
  "$root/scripts/roundtrip.sh" 2>&1)"; status=$?
bad=0
[ $status -eq 1 ] || { echo "FAIL want exit 1, got $status"; bad=1; }
want() {  # want <grep-pattern> <description>
  if grep -q -e "$1" <<<"$out"; then echo "PASS $2"
  else echo "FAIL $2 (no line matching '$1')"; bad=1; fi
}
want '^ok   pass$'                          "a passing case passes"
want '^ok   imports$'                       "a case importing a generated file passes"
want '^FAIL abort: abort_roundtrip.goose: exited nonzero' "an aborting program fails"
want "^FAIL noheader: x.txtpb has no '# proto-message:'"  "a txtpb without a message fails"
want '^FAIL noproto: no .*/noproto.proto'   "a case without a proto fails"
want '^FAIL noprogram: no \*_roundtrip.goose' "a case without a program fails"
want '^roundtrip: 4 failed'                 "the four failures are counted"
[ $bad = 0 ] || echo "$out"
exit $bad
