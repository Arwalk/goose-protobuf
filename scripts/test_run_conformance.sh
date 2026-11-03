#!/usr/bin/env bash
# Check run_conformance.sh's exit-code contract with a fake testee that
# answers parse_error to every request: nonzero iff a test fails outside
# the failure list, or a test inside it passes. Needs the runner
# (scripts/build_runner.sh) and python3.
# Usage: scripts/test_run_conformance.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fake" <<'PY'
#!/usr/bin/env python3
import struct, sys
i, o = sys.stdin.buffer, sys.stdout.buffer
while True:
    h = i.read(4)
    if len(h) < 4:
        break
    req = i.read(struct.unpack("<I", h)[0])
    # Empty FailureSet for the FailureSet request, parse_error otherwise.
    rep = b"\x1a\x00" if b"conformance.FailureSet" in req else b"\x0a\x01x"
    o.write(struct.pack("<I", len(rep)) + rep)
    o.flush()
PY
chmod +x "$tmp/fake"

passes=Required.Proto3.ProtobufInput.PrematureEofBeforeKnownNonRepeatedValue.INT32
fails=Required.Proto3.ProtobufInput.ValidDataScalar.INT32[2].ProtobufOutput
: > "$tmp/empty"
echo "$passes" > "$tmp/list_passes"
echo "$fails" > "$tmp/list_fails"

bad=0
expect() {  # expect <want-status: 0|nonzero> <failure-list> <test>
  FAILURE_LIST="$tmp/$2" "$root/scripts/run_conformance.sh" "$tmp/fake" \
    --test "$3" >"$tmp/log" 2>&1
  local got=$? ok=1
  if [ "$1" = 0 ]; then [ $got -eq 0 ] || ok=0; else [ $got -ne 0 ] || ok=0; fi
  if [ $ok = 1 ]; then echo "PASS want $1, list $2, $3"
  else echo "FAIL want $1 got $got, list $2, $3"; cat "$tmp/log"; bad=1; fi
}

expect 0       empty      "$passes"   # expected pass
expect nonzero list_passes "$passes"  # unexpected pass
expect nonzero empty      "$fails"    # unexpected failure
expect 0       list_fails "$fails"    # expected failure
exit $bad
