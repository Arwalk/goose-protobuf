#!/usr/bin/env bash
# Cross-implementation round trips: every tests/roundtrip/*/*.txtpb through
# generated Goose, protoc and Python protobuf. See scripts/interop.py.
# Usage: scripts/interop.sh [name...]   (default: every tests/roundtrip/*/)
# Env: PLUGIN     plugin binary (default: scripts/build_plugin.sh)
#      PROTO_DIR, ROUNDTRIP_DIR, PROTOC, GOOSE, TEST_TIMEOUT as scripts/roundtrip.sh
#      INTEROP_ECHO_WRAPPER  command put before the echo program (self-test)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
py="$root/.tools/python"
[ -d "$py/google/protobuf" ] ||
  { echo "error: no Python protobuf in $py; run scripts/install_toolchain.sh" >&2; exit 1; }

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  export PLUGIN="$root/build/protoc-gen-goose"
fi
PYTHONPATH="$py" exec python3 "$root/scripts/interop.py" "$@"
