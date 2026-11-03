#!/usr/bin/env bash
# Self-test for scripts/golden.sh, with a fake plugin that emits one file
# (smoke.goose) whose content comes from $FAKE_CONTENT, or random bytes if
# FAKE_CONTENT is unset. Checks that golden.sh passes on matching goldens,
# fails with a readable diff on a changed golden, fails on a golden that
# does not typecheck, fails on nondeterministic output, and that --update
# regenerates. Needs protoc, goose and python3.
# Usage: scripts/test_golden.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fake-plugin" <<'PY'
#!/usr/bin/env python3
import os, sys
sys.stdin.buffer.read()
path = os.environ.get("FAKE_CONTENT")
content = open(path, "rb").read() if path else os.urandom(8).hex().encode()

def ld(field, data):  # length-delimited field, lengths < 2**14
    n = len(data)
    v = bytes([n]) if n < 128 else bytes([n & 0x7F | 0x80, n >> 7])
    return bytes([field << 3 | 2]) + v + data

f = ld(1, b"smoke.goose") + ld(15, content)
sys.stdout.buffer.write(b"\x10\x01" + ld(15, f))  # features=1, file
PY
chmod +x "$tmp/fake-plugin"

mkdir -p "$tmp/protos"
cp "$root/tests/protos/smoke.proto" "$tmp/protos/"
printf 'fn smoke_id(x: i32) -> i32 {\n  return x;\n}\n' > "$tmp/good.goose"
printf 'fn smoke_id(x: i32) -> i32 {\n  return y;\n}\n' > "$tmp/bad.goose"

export PLUGIN="$tmp/fake-plugin" PROTO_DIR="$tmp/protos" GOLDEN_DIR="$tmp/golden"
bad=0
run() {  # run <want: 0|nonzero> <description> <grep-pattern|""> [golden.sh args]
  local want="$1" what="$2" pat="$3"; shift 3
  "$root/scripts/golden.sh" "$@" >"$tmp/log" 2>&1
  local got=$? ok=1
  if [ "$want" = 0 ]; then [ $got -eq 0 ] || ok=0; else [ $got -ne 0 ] || ok=0; fi
  if [ -n "$pat" ] && ! grep -q -e "$pat" "$tmp/log"; then ok=0; fi
  if [ $ok = 1 ]; then echo "PASS $what"
  else echo "FAIL $what (exit $got, want $want, pattern '$pat')"; cat "$tmp/log"; bad=1; fi
}

export FAKE_CONTENT="$tmp/good.goose"
run nonzero "missing golden fails"     "^+fn smoke_id"
run 0       "--update regenerates"     "" --update
cmp -s "$tmp/golden/smoke/smoke.goose" "$tmp/good.goose" ||
  { echo "FAIL --update did not write the golden"; bad=1; }
run 0       "matching golden passes"   "^ok   smoke"

sed -i 's/return x;/return x + 0;/' "$tmp/golden/smoke/smoke.goose"
run nonzero "changed golden fails with a diff" "^-  return x + 0;"

export FAKE_CONTENT="$tmp/bad.goose"
"$root/scripts/golden.sh" --update >/dev/null 2>&1
run nonzero "non-typechecking golden fails" "unknown identifier: y"

unset FAKE_CONTENT
run nonzero "nondeterministic output fails" "nondeterministic"
exit $bad
