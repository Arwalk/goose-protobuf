#!/usr/bin/env bash
# Self-test for scripts/buf_golden.sh, with a fake plugin that emits one file
# (smoke.goose) with the contents of $FAKE_CONTENT. Checks that it passes on a matching
# golden, and fails on a changed or missing golden, a file with no golden, a proto buf
# refuses and when nothing was generated. Needs buf and python3.
# Usage: scripts/test_buf_golden.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fake-plugin" <<'PY'
#!/usr/bin/env python3
import os, sys
sys.stdin.buffer.read()
content = open(os.environ["FAKE_CONTENT"], "rb").read()

def ld(field, data):  # length-delimited field, lengths < 128
    return bytes([field << 3 | 2, len(data)]) + data

f = ld(1, b"smoke.goose") + ld(15, content)
out = b"\x10\x01" + ld(15, f) if content else b"\x10\x01"
sys.stdout.buffer.write(out)  # features=1, file
PY
chmod +x "$tmp/fake-plugin"

mkdir -p "$tmp/protos" "$tmp/golden/smoke"
cp "$root/tests/protos/smoke.proto" "$tmp/protos/"
printf 'one\n' > "$tmp/one"
printf 'two\n' > "$tmp/two"
: > "$tmp/nothing"

export PLUGIN="$tmp/fake-plugin" PROTO_DIR="$tmp/protos" GOLDEN_DIR="$tmp/golden" FAKE_CONTENT="$tmp/one"
bad=0
run() {  # run <want: 0|nonzero> <description> <grep-pattern>
  local want="$1" what="$2" pat="$3"
  "$root/scripts/buf_golden.sh" >"$tmp/log" 2>&1
  local got=$? ok=1
  if [ "$want" = 0 ]; then [ $got -eq 0 ] || ok=0; else [ $got -ne 0 ] || ok=0; fi
  grep -q -e "$pat" "$tmp/log" || ok=0
  if [ $ok = 1 ]; then echo "PASS $what"
  else echo "FAIL $what (exit $got, want $want, pattern '$pat')"; cat "$tmp/log"; bad=1; fi
}

cp "$tmp/one" "$tmp/golden/smoke/smoke.goose"
run 0 "a matching golden passes" "1 protos, 1 files identical"

cp "$tmp/two" "$tmp/golden/smoke/smoke.goose"
run nonzero "a changed golden fails with a diff" "^-two"

rm "$tmp/golden/smoke/smoke.goose"
run nonzero "a file with no golden fails" "^+one"

cp "$tmp/one" "$tmp/golden/smoke/other.goose"
cp "$tmp/one" "$tmp/golden/smoke/smoke.goose"
run nonzero "a golden with no file fails" "buf's output differs"
rm "$tmp/golden/smoke/other.goose"

rm -rf "$tmp/golden/smoke"
FAKE_CONTENT="$tmp/nothing" run nonzero "generating nothing at all fails" "nothing was compared"
mkdir -p "$tmp/golden/smoke"; cp "$tmp/one" "$tmp/golden/smoke/smoke.goose"

printf 'not a proto\n' > "$tmp/protos/broken.proto"
run nonzero "a proto buf refuses fails" "FAIL broken: buf generate failed"
exit $bad
