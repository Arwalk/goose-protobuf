#!/usr/bin/env bash
# The feature defaults of the editions the plugin takes, as protoc computes them,
# against the committed copy that generator-goose/features.goose is tested with.
# Usage: scripts/edition_defaults.sh [--update]
# Env: PROTOC (default protoc; .tools/bin first)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
committed="$root/generator-goose/edition_defaults.binpb"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$protoc" --edition_defaults_out="$tmp/defaults" \
  --edition_defaults_minimum=PROTO2 --edition_defaults_maximum=2023 \
  -I "$root/third_party/protobuf/src" google/protobuf/descriptor.proto

if [ "${1:-}" = "--update" ]; then
  cp "$tmp/defaults" "$committed"
  echo "updated $committed"
elif cmp -s "$tmp/defaults" "$committed"; then
  echo "ok   edition defaults"
else
  echo "FAIL edition defaults differ from protoc's: scripts/edition_defaults.sh --update" >&2
  exit 1
fi
