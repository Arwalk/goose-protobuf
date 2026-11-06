#!/usr/bin/env bash
# Unit tests of generator-goose/. Each tests/selfhost/*_unit.goose is a program
# built with --debug next to the generator's files, its bindings, the runtime and
# unit_support.goose, and run; it passes iff it exits 0. They are not *_test.goose, which scripts/goose_tests.sh builds where they
# are. Then the plugin is built, for what only a process shows.
# Usage: scripts/selfhost_tests.sh
# Env: GOOSE (default goose; .tools/bin first),
#      GENERATOR_SRC (default generator-goose/; scripts/test_selfhost_tests.sh
#      points it at changed copies)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
goose="${GOOSE:-goose}"
src="${GENERATOR_SRC:-$root/generator-goose}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$src"/. "$tmp/"
cp "$root/tests/selfhost/unit_support.goose" "$tmp/"
"$root/scripts/vendor_runtime.sh" "$tmp"

failed=0 count=0
for t in "$root"/tests/selfhost/*_unit.goose; do
  name="$(basename "$t")"
  cp "$t" "$tmp/"
  if ! (cd "$tmp" && "$goose" build "$name" --debug -o test) >"$tmp/log" 2>&1; then
    echo "FAIL $name (build failed)"; cat "$tmp/log"; failed=$((failed + 1)); continue
  fi
  if "$tmp/test" >"$tmp/log" 2>&1; then
    echo "PASS $name"; count=$((count + 1))
  else
    echo "FAIL $name"; sed 's/^/    /' "$tmp/log"; failed=$((failed + 1))
  fi
  rm -f "$tmp/$name" "$tmp/test"
done

# What only the built plugin shows: its exit status, stdout and stderr.
check_plugin() {  # check_plugin <what> <want status> <want stdout, hex> <want on stderr> <input file>
  local status=0
  "$tmp/plugin" <"$5" >"$tmp/out" 2>"$tmp/err" || status=$?
  local hex; hex="$(od -An -tx1 "$tmp/out" | tr -d ' \n')"
  if [ "$status" != "$2" ] || [ "$hex" != "$3" ] || { [ -n "$4" ] && ! grep -q "$4" "$tmp/err"; }; then
    echo "FAIL plugin: $1: exit $status, stdout $hex, stderr: $(cat "$tmp/err")"; failed=$((failed + 1))
  else
    echo "PASS plugin: $1"; count=$((count + 1))
  fi
}
if (cd "$tmp" && "$goose" build main.goose -o plugin) >"$tmp/log" 2>&1; then
  : >"$tmp/empty.bin"
  check_plugin "an empty request" 0 100318e60720ea07 '' "$tmp/empty.bin"
  printf '\012\005a' >"$tmp/cut.bin"
  check_plugin "a truncated request" 1 "" 'failed to decode CodeGeneratorRequest: truncated input' "$tmp/cut.bin"
else
  echo "FAIL the plugin does not build"; cat "$tmp/log"; failed=$((failed + 1))
fi

echo "selfhost_tests: $count passed, $failed failed"
[ "$failed" -eq 0 ] && [ "$count" -gt 0 ]
