#!/usr/bin/env bash
# Smoke test for protoc-gen-goose:
# - protoc runs the plugin on tests/protos/smoke.proto, exits 0, and writes
#   exactly smoke.goose (its content is checked by scripts/golden.sh);
# - a malformed CodeGeneratorRequest makes the plugin exit nonzero with a
#   message on stderr.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "$root/.tools/bin" ]]; then
  export PATH="$root/.tools/bin:$PATH"
fi

"$root/scripts/build_plugin.sh"
plugin="$root/build/protoc-gen-goose"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/out"

protoc --plugin=protoc-gen-goose="$plugin" --goose_out="$tmp/out" \
  -I "$root/tests/protos" "$root/tests/protos/smoke.proto"

if [[ "$(ls -A "$tmp/out")" != "smoke.goose" ]]; then
  echo "FAIL: plugin wrote, instead of smoke.goose:" >&2
  ls -A "$tmp/out" >&2
  exit 1
fi
echo "PASS: protoc exits 0 and writes smoke.goose"

status=0
printf '\x0a\x05a' | "$plugin" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
if [[ $status -eq 0 ]]; then
  echo "FAIL: malformed request exited 0" >&2
  exit 1
fi
if [[ ! -s "$tmp/stderr" ]]; then
  echo "FAIL: malformed request printed nothing on stderr" >&2
  exit 1
fi
echo "PASS: malformed request exits $status: $(cat "$tmp/stderr")"
