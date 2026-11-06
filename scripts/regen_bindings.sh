#!/usr/bin/env bash
# The plugin is built on its own output: generator-goose/google/ holds the bindings
# of descriptor.proto and plugin.proto that it generates. Checks that it writes them
# unchanged. After a change to what the plugin writes, --update accepts the new ones;
# run it until it reports no change, as the plugin that wrote them is then their own.
# Usage: scripts/regen_bindings.sh [--update]
# Env: PROTOC, GOOSE (default protoc, goose; .tools/bin first)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
include="$(cd "$(dirname "$(readlink -f "$(command -v "$protoc")")")/../include" && pwd)"
committed="$root/generator-goose/google"

"$root/scripts/build_plugin.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$protoc" --plugin=protoc-gen-goose="$root/build/protoc-gen-goose" --goose_out="$tmp" -I "$include" \
  google/protobuf/compiler/plugin.proto google/protobuf/descriptor.proto

if diff -ruN "$committed" "$tmp/google" >"$tmp/diff"; then
  echo "ok   the plugin writes its own bindings unchanged"
elif [ "${1:-}" = "--update" ]; then
  rm -rf "$committed"
  cp -R "$tmp/google" "$committed"
  echo "updated $committed: rerun until there is no change"
else
  head -40 "$tmp/diff"
  echo "FAIL the plugin's bindings differ: scripts/regen_bindings.sh --update" >&2
  exit 1
fi
