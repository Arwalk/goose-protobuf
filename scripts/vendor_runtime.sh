#!/usr/bin/env bash
# Copies the pb_wire package into a directory, as a program's own files: the
# entry as pb_wire.goose, the well-known types as pb_wire/wkt/. Goose finds
# `import pb_wire;` and `import pb_wire.wkt.any;` there without a declaration.
# Usage: scripts/vendor_runtime.sh <dir>
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 <dir>" >&2; exit 2; }
cp "$root/runtime/pb_wire.goose" "$1/pb_wire.goose"
mkdir -p "$1/pb_wire"
cp -R "$root/wkt" "$1/pb_wire/"
