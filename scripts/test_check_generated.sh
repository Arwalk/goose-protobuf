#!/usr/bin/env bash
# Self-test for scripts/check_generated.sh, with a fake plugin that emits
# one file (smoke.goose) whose content comes from $FAKE_CONTENT: code that
# typechecks passes, code that does not fails, code with a goose warning
# fails. Needs protoc, goose and python3.
# Usage: scripts/test_check_generated.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fake-plugin" <<'PY'
#!/usr/bin/env python3
import os, sys
sys.stdin.buffer.read()
content = open(os.environ["FAKE_CONTENT"], "rb").read()

def ld(field, data):  # length-delimited field, lengths < 2**14
    n = len(data)
    v = bytes([n]) if n < 128 else bytes([n & 0x7F | 0x80, n >> 7])
    return bytes([field << 3 | 2]) + v + data

f = ld(1, b"smoke.goose") + ld(15, content)
sys.stdout.buffer.write(b"\x10\x01" + ld(15, f))  # features=1, file
PY
chmod +x "$tmp/fake-plugin"

printf 'fn smoke_id(x: i32) -> i32 {\n  return x;\n}\n' > "$tmp/good.goose"
printf 'fn smoke_id(x: i32) -> i32 {\n  return y;\n}\n' > "$tmp/bad.goose"
printf 'fn smoke_wide(x: u32) -> u64 {\n  return x as u64;\n}\n' > "$tmp/warn.goose"

export PLUGIN="$tmp/fake-plugin"
bad=0
run() {  # run <want: 0|nonzero> <content> <grep-pattern> <description>
  FAKE_CONTENT="$tmp/$2" "$root/scripts/check_generated.sh" \
    -I "$root/tests/protos" smoke.proto >"$tmp/log" 2>&1
  local got=$? ok=1
  if [ "$1" = 0 ]; then [ $got -eq 0 ] || ok=0; else [ $got -ne 0 ] || ok=0; fi
  grep -q -e "$3" "$tmp/log" || ok=0
  if [ $ok = 1 ]; then echo "PASS $4"
  else echo "FAIL $4 (exit $got, want $1, pattern '$3')"; cat "$tmp/log"; bad=1; fi
}
run 0       good.goose '^ok   smoke.goose'                    "code that typechecks passes"
run nonzero bad.goose  '^FAIL smoke.goose: goose check failed' "code that does not typecheck fails"
run nonzero warn.goose '^FAIL smoke.goose: goose check warned' "code with a warning fails"
exit $bad
