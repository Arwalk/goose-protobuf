#!/usr/bin/env bash
# Self-test for scripts/interop.sh on scripts/testdata/interop/, with the real
# plugin: `pass` passes and `noheader` and `noproto` fail; then the echo's output
# is spoiled in three ways, and each must be caught, with a hex diff.
# Usage: scripts/test_interop.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
data="$root/scripts/testdata/interop"
export PROTO_DIR="$data/protos" ROUNDTRIP_DIR="$data/cases"
bad=0
want() {  # want <output> <grep-pattern> <description>
  if grep -q -e "$2" <<<"$1"; then echo "PASS $3"
  else echo "FAIL $3 (no line matching '$2')"; echo "$1"; bad=1; fi
}
wantexit() {  # wantexit <got> <want> <description>
  if [ "$1" = "$2" ]; then echo "PASS $3"
  else echo "FAIL $3: exit $1, want $2"; bad=1; fi
}

out="$("$root/scripts/interop.sh" pass 2>&1)"; status=$?
wantexit $status 0 "a clean case exits 0"
want "$out" '^ok   pass (1)$' "a clean case passes"

out="$("$root/scripts/interop.sh" noheader noproto 2>&1)"; status=$?
wantexit $status 1 "harness failures exit 1"
want "$out" "^FAIL noheader: x.txtpb has no '# proto-message:'" "a txtpb without a message fails"
want "$out" '^FAIL noproto: no .*/noproto' "a case without a proto fails"

spoiled() {  # spoiled <mode> <step> <description>
  local out status
  out="$(INTEROP_BREAK="$1" INTEROP_ECHO_WRAPPER="$data/break_echo.py" \
    "$root/scripts/interop.sh" pass 2>&1)"; status=$?
  wantexit $status 1 "$3: exits 1"
  want "$out" "^FAIL pass/five: $2" "$3: named"
  want "$out" 'first difference at offset' "$3: hex diff"
}
spoiled flip 'protoc->goose->protoc' "another value"
spoiled truncate 'protoc->goose->protoc' "bytes protoc cannot read"
spoiled double 'goose canonical' "a byte-only difference"
exit $bad
