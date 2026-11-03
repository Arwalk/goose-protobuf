#!/usr/bin/env bash
# Goose unit tests (Goose has no `goose test`).
# Usage: scripts/goose_tests.sh [dir-or-file...]   (default: tests/)
# Builds every *_test.goose under the given paths with `goose build
# --debug` and runs it. A test passes iff it builds and exits 0; a failed
# build, an abort (including a --debug overflow/range check) or a nonzero
# exit fails it, and its output is printed. Exits nonzero if any test
# fails, or if paths were given explicitly and hold no tests.
# Tests import the runtime as a directory package, e.g. from tests/runtime/:
#   import pb_wire from "../../runtime";
# Env: GOOSE (default goose; .tools/bin first), TEST_TIMEOUT (seconds, 120)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
goose="${GOOSE:-goose}"
limit="${TEST_TIMEOUT:-120}"
command -v "$goose" >/dev/null || { echo "error: goose not found; see TOOLCHAIN.md" >&2; exit 1; }

explicit=1
if [ $# -eq 0 ]; then set -- "$root/tests"; explicit=0; fi

tests=()
while IFS= read -r -d '' f; do tests+=("$f"); done < <(
  for p in "$@"; do
    if [ -f "$p" ]; then printf '%s\0' "$p"
    elif [ -d "$p" ]; then find "$p" -name '*_test.goose' -type f -print0
    else echo "error: no such file or directory: $p" >&2; fi
  done | sort -z)

if [ ${#tests[@]} -eq 0 ]; then
  echo "goose_tests: no *_test.goose found in $*"
  exit $explicit
fi

runner=()
command -v timeout >/dev/null && runner=(timeout "$limit")

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failed=()
for t in "${tests[@]}"; do
  rel="${t#$root/}"
  bin="$tmp/test"
  if ! "$goose" build "$t" --debug -o "$bin" >"$tmp/log" 2>&1; then
    echo "FAIL $rel (build failed)"
    grep -v '^parsed ok\|^typechecked ok\|^bce:\|^wrote \|^built ' "$tmp/log" | sed 's/^/    /'
    failed+=("$rel"); continue
  fi
  "${runner[@]}" "$bin" >"$tmp/log" 2>&1
  status=$?
  if [ $status -eq 0 ]; then
    echo "PASS $rel"
  else
    reason="exit $status"
    [ $status -ge 128 ] && reason="killed by signal $((status - 128)) (abort?)"
    [ $status -eq 124 ] && [ ${#runner[@]} -gt 0 ] && reason="timed out after ${limit}s"
    echo "FAIL $rel ($reason)"
    sed 's/^/    /' "$tmp/log"
    failed+=("$rel")
  fi
  rm -f "$bin"
done

echo "goose_tests: $(( ${#tests[@]} - ${#failed[@]} )) passed, ${#failed[@]} failed"
if [ ${#failed[@]} -gt 0 ]; then
  printf '  failed: %s\n' "${failed[@]}"
  exit 1
fi
