#!/usr/bin/env bash
# The plugin's bindings of descriptor.proto and plugin.proto, on real requests. For each proto of
# tests/protos, and for the conformance suite's when the submodule is checked out,
# it captures the CodeGeneratorRequest protoc sends a plugin, and decodes and
# encodes it through the bindings: the bytes must come back the same. A truncated
# request must fail.
# Usage: scripts/selfhost_bindings.sh
# Env: PROTOC, GOOSE (default protoc, goose; .tools/bin first)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$root/generator-goose/google" "$tmp/"
cp "$root/tests/selfhost/request_echo.goose" "$tmp/"
"$root/scripts/vendor_runtime.sh" "$tmp"
(cd "$tmp" && "$goose" build request_echo.goose --debug -o echo) >"$tmp/log" 2>&1 ||
  { cat "$tmp/log"; exit 1; }

# A plugin that keeps the request. Its empty reply says nothing of editions, which
# protoc rejects after the plugin has run, so protoc's exit status means nothing.
cat >"$tmp/dump" <<SH
#!/bin/sh
cat >"$tmp/req.bin"
SH
chmod +x "$tmp/dump"

failed=0 count=0
check() {  # check <what> <protoc args...>
  local what="$1"; shift
  rm -f "$tmp/req.bin"
  "$protoc" --plugin=protoc-gen-dump="$tmp/dump" --dump_out="$tmp" "$@" >/dev/null 2>&1
  [ -s "$tmp/req.bin" ] || { echo "FAIL $what: no request captured"; failed=$((failed + 1)); return; }
  if ! "$tmp/echo" <"$tmp/req.bin" >"$tmp/out.bin" 2>"$tmp/err"; then
    echo "FAIL $what: $(cat "$tmp/err")"; failed=$((failed + 1)); return
  fi
  if ! cmp -s "$tmp/req.bin" "$tmp/out.bin"; then
    echo "FAIL $what: $(cmp "$tmp/req.bin" "$tmp/out.bin")"; failed=$((failed + 1)); return
  fi
  count=$((count + 1))
}

for p in "$root"/tests/protos/*.proto; do
  check "$(basename "$p")" -I "$root/tests/protos" "$p"
done
pb="$root/third_party/protobuf"
if [ -f "$pb/src/google/protobuf/test_messages_proto3.proto" ]; then
  for p in google/protobuf/test_messages_proto3.proto google/protobuf/test_messages_proto2.proto \
           editions/golden/test_messages_proto3_editions.proto \
           editions/golden/test_messages_proto2_editions.proto \
           conformance/test_protos/test_messages_edition2023.proto; do
    check "$p" -I "$pb/src" -I "$pb" "$p"
  done
fi

# The last request, cut short, must not pass.
head -c 100 "$tmp/req.bin" >"$tmp/cut.bin"
if "$tmp/echo" <"$tmp/cut.bin" >/dev/null 2>&1; then
  echo "FAIL a truncated request decoded"; failed=$((failed + 1))
fi

if [ $failed -gt 0 ]; then echo "selfhost_bindings: $failed failed"; exit 1; fi
echo "selfhost_bindings: $count requests identical"
