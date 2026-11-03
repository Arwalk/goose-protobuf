#!/usr/bin/env bash
# Run the protobuf conformance suite against a Goose testee binary.
# Usage: scripts/run_conformance.sh <testee-binary> [runner args...]
#   e.g. scripts/run_conformance.sh build/testee --maximum_edition 2023
# Env: RUNNER (default build/pb/conformance_test_runner)
#      FAILURE_LIST (default conformance/failure_list_goose.txt)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="${RUNNER:-$root/build/pb/conformance_test_runner}"
failure_list="${FAILURE_LIST:-$root/conformance/failure_list_goose.txt}"

if [ $# -lt 1 ]; then
  echo "usage: $0 <testee-binary> [runner args...]" >&2
  exit 2
fi
testee="$1"; shift

[ -x "$runner" ] || { echo "error: no runner at $runner; run scripts/build_runner.sh" >&2; exit 1; }
[ -x "$testee" ] || { echo "error: testee $testee not executable" >&2; exit 1; }

exec "$runner" --failure_list "$failure_list" "$@" "$testee"
