#!/usr/bin/env bash
# Prints the given protos and everything they import, transitively, one per
# line, as protoc names them. protoc generates only the files on its command
# line, and a generated file imports the ones whose types it uses, so a build
# or check of it needs them generated too.
# Usage: scripts/proto_closure.sh [-I dir]... file.proto...
# Env: PROTOC (default protoc; .tools/bin first)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# A proto's own unused imports are no business of this script's.
"$protoc" --include_imports --descriptor_set_out="$tmp/set" "$@" 2>"$tmp/log" ||
  { cat "$tmp/log" >&2; exit 1; }
"$protoc" --decode=google.protobuf.FileDescriptorSet \
  google/protobuf/descriptor.proto <"$tmp/set" |
  tr -d '\r' | # protoc's text ends its lines with CRLF on Windows
  sed -n 's/^  name: "\(.*\)"$/\1/p'
