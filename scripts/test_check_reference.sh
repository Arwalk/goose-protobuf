#!/usr/bin/env bash
# Self-test of scripts/check_reference.py: it must pass the real page and catch each
# kind of mistake in a changed copy.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check="$root/scripts/check_reference.py"
page="$root/docs/generated-code.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failed=0

"$check" >/dev/null || { echo "FAIL the real page does not pass"; failed=1; }

# expect_catch <what> <text in the output> <python expression on page text s>
expect_catch() {
  python3 -c "
import sys
s = open(sys.argv[1]).read()
t = $3
assert t != s, 'the change did nothing'
open(sys.argv[2], 'w').write(t)
" "$page" "$tmp/page.md"
  if out="$("$check" "$tmp/page.md")"; then
    echo "FAIL $1: not caught"; failed=1
  elif ! grep -qF "$2" <<<"$out"; then
    echo "FAIL $1: wrong message: $out"; failed=1
  else
    echo "ok   $1"
  fi
}

expect_catch "a function that does not exist" "M_f_nope" \
  "s.replace('\`M_add_f(m) -> S&\`', '\`M_f_nope(m) -> S&\`')"
expect_catch "wrong parameters" "takes (m, i, v)" \
  "s.replace('\`M_set_f(m, i, v)\`', '\`M_set_f(m, v)\`')"
expect_catch "a wrong return type" "M_f_len returns 'i64'" \
  "s.replace('\`M_f_len(m) -> i64\`', '\`M_f_len(m) -> bool\`', 1)"
expect_catch "a function with no row" "no row for Lists_names_at" \
  "s.replace('| \`M_f_at(m, i) -> u8[:]\` | A view of the contents of value \`i\` |\n', '')"
expect_catch "a name in no table" "M_f_gone is on the page" \
  "s.replace('There is no getter', 'Use \`M_f_gone\`. There is no getter', 1)"
expect_catch "an internal name" "pb_Span is not public" \
  "s + 'See pb_Span.\n'"

[ "$failed" = 0 ] && echo "test_check_reference: all caught"
exit "$failed"
