#!/usr/bin/env bash
# Builds the self-hosted plugin, generator-goose/, to build/protoc-gen-goose-self.
# The Goose bindings of descriptor.proto and plugin.proto are generated here with
# the Zig plugin, into build/selfhost-src next to a copy of generator-goose/ and
# of the runtime, and are not committed.
# Usage: scripts/build_selfhost.sh [out]   (default build/protoc-gen-goose-self)
# Env: PLUGIN, PROTOC, GOOSE (default: zig build; protoc, goose; .tools/bin first),
#      GOOSE_FLAGS (extra goose build flags, e.g. --debug)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
out="${1:-$root/build/protoc-gen-goose-self}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
include="$(cd "$(dirname "$(readlink -f "$(command -v "$protoc")")")/../include" && pwd)"
if [ -z "${PLUGIN:-}" ]; then
  (cd "$root/generator" && zig build) || { echo "error: zig build failed" >&2; exit 1; }
  PLUGIN="$root/generator/zig-out/bin/protoc-gen-goose"
fi

stage="$root/build/selfhost-src"
rm -rf "$stage"; mkdir -p "$stage"
"$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$stage" -I "$include" \
  google/protobuf/compiler/plugin.proto google/protobuf/descriptor.proto
cp "$root"/generator-goose/*.goose "$stage/"
"$root/scripts/vendor_runtime.sh" "$stage"

mkdir -p "$(dirname "$out")"
# shellcheck disable=SC2086
(cd "$stage" && "$goose" build main.goose ${GOOSE_FLAGS:-} -o "$out") >&2
