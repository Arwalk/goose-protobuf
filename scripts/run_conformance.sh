#!/usr/bin/env bash
# Run the protobuf conformance suite against a Goose testee binary.
# Usage: scripts/run_conformance.sh [testee-binary] [runner args...]
#   scripts/run_conformance.sh                        # build + run default testee
#   scripts/run_conformance.sh --maximum_edition 2023 # same, with runner flags
#   scripts/run_conformance.sh build/testee --test <name> --enforce_recommended
# With no testee (or when the first argument is a flag), the default testee
# conformance/testee.goose is built to build/testee first if it is missing
# or older than its sources. Runner flags (--maximum_edition,
# --enforce_recommended, --test, ...) are passed through unchanged.
# Exit status is the runner's: nonzero iff a test fails that is not in the
# failure list, or a test in the failure list passes.
# Env: RUNNER (default build/pb/conformance_test_runner)
#      FAILURE_LIST (default conformance/failure_list_goose.txt)
#      GOOSE (default goose)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="${RUNNER:-$root/build/pb/conformance_test_runner}"
failure_list="${FAILURE_LIST:-$root/conformance/failure_list_goose.txt}"
goose="${GOOSE:-goose}"

die() { echo "error: $*" >&2; exit 1; }

# Build the default testee unless it is newer than every source it uses.
build_default_testee() {
  local out="$root/build/testee" src="$root/conformance/testee.goose" f
  local stale=0
  [ -x "$out" ] || stale=1
  if [ "$stale" = 0 ]; then
    for f in "$src" "$root/conformance/io.c" "$root/conformance/testee.build" \
             "$root"/runtime/*.goose; do
      [ -e "$f" ] && [ "$f" -nt "$out" ] && { stale=1; break; }
    done
  fi
  if [ "$stale" = 1 ]; then
    command -v "$goose" >/dev/null || die "goose not found; see TOOLCHAIN.md"
    mkdir -p "$root/build"
    echo "building default testee: $out" >&2
    "$goose" build "$src" -o "$out" >&2
  fi
  testee="$out"
}

if [ $# -eq 0 ] || [ "${1#-}" != "$1" ]; then
  build_default_testee
else
  testee="$1"; shift
fi

[ -x "$runner" ] || die "no runner at $runner; run scripts/build_runner.sh"
[ -x "$testee" ] || die "testee $testee not executable"

exec "$runner" --failure_list "$failure_list" "$@" "$testee"
