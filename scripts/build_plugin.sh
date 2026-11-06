#!/usr/bin/env bash
# Builds the plugin, generator-goose/, to build/protoc-gen-goose: its committed
# bindings of descriptor.proto and plugin.proto (scripts/regen_bindings.sh) next to
# a copy of the runtime, in build/plugin-src. Needs only Goose. Does nothing if the
# binary is newer than what it is built from. Silent unless the build fails.
# Usage: scripts/build_plugin.sh [out]   (default build/protoc-gen-goose)
# Env: GOOSE (default goose; .tools/bin first),
#      GOOSE_FLAGS (extra goose build flags, e.g. --debug)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
goose="${GOOSE:-goose}"
out="${1:-$root/build/protoc-gen-goose}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

if [ -x "$out" ] && [ -z "${GOOSE_FLAGS:-}" ] && [ -z "$(find "$root/generator-goose" "$root/runtime" "$root/wkt" \
    "$root/scripts/build_plugin.sh" -type f -newer "$out" -print -quit)" ]; then
  exit 0
fi

stage="$root/build/plugin-src"
rm -rf "$stage"; mkdir -p "$stage" "$(dirname "$out")"
cp -R "$root"/generator-goose/. "$stage/"
"$root/scripts/vendor_runtime.sh" "$stage"
# shellcheck disable=SC2086
if ! (cd "$stage" && "$goose" build main.goose ${GOOSE_FLAGS:-} -o "$out") >"$stage/build.log" 2>&1; then
  cat "$stage/build.log" >&2
  exit 1
fi
