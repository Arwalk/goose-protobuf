#!/usr/bin/env bash
# Unit tests of generator-goose/. Each tests/selfhost/*_unit.goose is a program
# built with --debug next to the generator's files, its generated bindings, the
# runtime and edition_defaults.binpb, and run; it passes iff it exits 0. They are
# not *_test.goose, which scripts/goose_tests.sh builds where they are.
# Usage: scripts/selfhost_tests.sh
# Env: PLUGIN, PROTOC, GOOSE (default: zig build; protoc, goose; .tools/bin first),
#      GENERATOR_SRC (default generator-goose/; scripts/test_selfhost_tests.sh
#      points it at changed copies)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
src="${GENERATOR_SRC:-$root/generator-goose}"
include="$(cd "$(dirname "$(readlink -f "$(command -v "$protoc")")")/../include" && pwd)"
if [ -z "${PLUGIN:-}" ]; then
  (cd "$root/generator" && zig build) || { echo "error: zig build failed" >&2; exit 1; }
  PLUGIN="$root/generator/zig-out/bin/protoc-gen-goose"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$tmp" -I "$include" \
  google/protobuf/compiler/plugin.proto google/protobuf/descriptor.proto || exit 1
cp "$src"/*.goose "$tmp/"
rm "$tmp/main.goose"  # each test has its own main
cp "$root/generator/src/edition_defaults.binpb" "$tmp/"
"$root/scripts/vendor_runtime.sh" "$tmp"

failed=0 count=0
for t in "$root"/tests/selfhost/*_unit.goose; do
  name="$(basename "$t")"
  cp "$t" "$tmp/"
  if ! (cd "$tmp" && "$goose" build "$name" --debug -o test) >"$tmp/log" 2>&1; then
    echo "FAIL $name (build failed)"; cat "$tmp/log"; failed=$((failed + 1)); continue
  fi
  if "$tmp/test" >"$tmp/log" 2>&1; then
    echo "PASS $name"; count=$((count + 1))
  else
    echo "FAIL $name"; sed 's/^/    /' "$tmp/log"; failed=$((failed + 1))
  fi
  rm -f "$tmp/$name" "$tmp/test"
done

echo "selfhost_tests: $count passed, $failed failed"
[ "$failed" -eq 0 ] && [ "$count" -gt 0 ]
