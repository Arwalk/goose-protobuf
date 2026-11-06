#!/usr/bin/env bash
# Self-test of scripts/check_links.py: it passes this repository, passes every good
# kind of link, and fails each kind of bad one, naming the file and line.
# Usage: scripts/test_check_links.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check="$root/scripts/check_links.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0
report() {
  if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; cat "$tmp/log"; bad=1; fi
}

"$check" >"$tmp/log" 2>&1; report $? "this repository passes"

repo="$tmp/repo"
mkdir -p "$repo/docs" "$repo/third_party"
git -C "$repo" init -q
cat > "$repo/docs/target.md" <<'MD'
# Target page
## The `code` Part, again
## Twice
## Twice
<a name="by-hand"></a>
MD
printf 'x\n' > "$repo/file with space.txt"
good() {  # adds $1 to a page, which must still pass
  printf '%s\n' "$1" > "$repo/page.md"
  git -C "$repo" add -A
  "$check" "$repo" >"$tmp/log" 2>&1; report $? "passes: $1"
}
wrong() {  # adds $1 to line 2 of a page, which must fail with $2
  printf 'first\n%s\n' "$1" > "$repo/page.md"
  git -C "$repo" add -A
  local ok=0
  if "$check" "$repo" >"$tmp/log" 2>&1; then ok=1
  elif ! grep -qF "page.md:2: $2" "$tmp/log"; then ok=1; fi
  report $ok "fails: $1"
}

good '[a](docs/target.md) ![b](docs/target.md "title") [c](docs) [d](file%20with%20space.txt)'
good '[a](docs/target.md#target-page) [b](docs/target.md#the-code-part-again)'
good '[a](docs/target.md#twice-1) [b](docs/target.md#by-hand) [c](#own) 
## Own'
good '[a](https://example.org/missing) [b](mailto:a@example.org)'
good '`[a](missing.md)`'
good '```
[a](missing.md)
```'

wrong '[a](missing.md)' 'no such file: missing.md'
wrong '![a](docs/missing.png)' 'no such file: docs/missing.png'
wrong '[a [b] c](docs/missing.md)' 'no such file: docs/missing.md'
wrong '<a href="missing.html">a</a>' 'no such file: missing.html'
wrong '[a]: missing.md' 'no such file: missing.md'
wrong '[a](docs/target.md#nothing)' 'no such heading: docs/target.md#nothing'
wrong '[a](docs/target.md#twice-2)' 'no such heading: docs/target.md#twice-2'
wrong '[a](#nothing)' 'no such heading: #nothing'

# Only tracked files count, and not third_party/.
printf '[a](missing.md)\n' > "$repo/page.md"
git -C "$repo" rm -qf --cached page.md
printf '[a](missing.md)\n' > "$repo/third_party/vendored.md"
git -C "$repo" add third_party
"$check" "$repo" >"$tmp/log" 2>&1; report $? "untracked files and third_party/ are left alone"

exit $bad
