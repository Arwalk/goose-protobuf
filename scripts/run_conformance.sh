#!/usr/bin/env bash
# Run the protobuf conformance suite against a Goose testee binary.
# Usage: scripts/run_conformance.sh [testee-binary] [runner args...]
#   scripts/run_conformance.sh                        # build + run default testee
#   scripts/run_conformance.sh --maximum_edition 2023 # same, with runner flags
#   scripts/run_conformance.sh build/testee --test <name> --enforce_recommended
# With no testee (or when the first argument is a flag), the default testee
# conformance/testee.goose is built to build/testee first, with
# scripts/build_testee.sh (which generates its bindings). Runner flags (--maximum_edition,
# --enforce_recommended, --test, ...) are passed through unchanged.
# Exit status is the runner's: nonzero iff a test fails that is not in the
# failure list, or a test in the failure list passes.
# Env: RUNNER (default build/pb/conformance_test_runner)
#      FAILURE_LIST (default conformance/failure_list_goose.txt)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="${RUNNER:-$root/build/pb/conformance_test_runner}"
failure_list="${FAILURE_LIST:-$root/conformance/failure_list_goose.txt}"

die() { echo "error: $*" >&2; exit 1; }

# Build the default testee from freshly generated bindings. The build
# depends on the generator, the runtime and the protobuf sources, so it is
# always redone (zig build and goose build are quick when nothing changed).
build_default_testee() {
  testee="$root/build/testee"
  echo "building default testee: $testee" >&2
  "$root/scripts/build_testee.sh" "$testee"
}

if [ $# -eq 0 ] || [ "${1#-}" != "$1" ]; then
  build_default_testee
else
  testee="$1"; shift
fi

[ -x "$runner" ] || die "no runner at $runner; run scripts/build_runner.sh"
[ -x "$testee" ] || die "testee $testee not executable"

exec "$runner" --failure_list "$failure_list" "$@" "$testee"
