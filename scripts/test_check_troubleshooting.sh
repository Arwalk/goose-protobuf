#!/usr/bin/env bash
# Self-test of scripts/check_troubleshooting.py: it must pass the real page, fail one
# that lost a message, and fail when a mistake no longer prints what the page says.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check="$root/scripts/check_troubleshooting.py"
page="$root/docs/troubleshooting.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failed=0

"$check" >/dev/null || { echo "FAIL the real page does not pass"; failed=1; }

grep -vF 'unknown function: p::P_tags' "$page" >"$tmp/lost.md"
if out="$("$check" "$tmp/lost.md")"; then
  echo "FAIL a message missing from the page: not caught"; failed=1
elif ! grep -qF "the page does not show 'error: unknown function: p::P_tags'" <<<"$out"; then
  echo "FAIL a message missing from the page: wrong message: $out"; failed=1
else
  echo "ok   a message missing from the page"
fi

# A copy of the script that expects another message from the same mistake.
sed 's/"pb_Span { 0, 1 }"/"pb_Span { 9, 9 }"/; s#^ROOT = .*#ROOT = Path("'"$root"'")#' "$check" >"$tmp/changed.py"
if out="$(python3 "$tmp/changed.py")"; then
  echo "FAIL a mistake that prints something else: not caught"; failed=1
elif ! grep -qF "no longer prints 'pb_Span { 9, 9 }'" <<<"$out"; then
  echo "FAIL a mistake that prints something else: wrong message: $out"; failed=1
else
  echo "ok   a mistake that prints something else"
fi

[ "$failed" = 0 ] && echo "test_check_troubleshooting: all caught"
exit "$failed"
