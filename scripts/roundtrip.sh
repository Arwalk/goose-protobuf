#!/usr/bin/env bash
# Round-trip tests: generated code against protoc's own encoding.
# Usage: scripts/roundtrip.sh [name...]   (default: every tests/roundtrip/*/)
#
# For each tests/roundtrip/<name>/:
#   1. generate tests/protos/<name>.proto and the files it imports with the
#      plugin into a temp dir, next to a copy of runtime/pb_wire.goose and
#      of every file in tests/roundtrip/<name>/ (an imported a/b.proto is
#      imported by the program as `import a.b;`);
#   2. encode each <case>.txtpb with `protoc --encode=<message>` into
#      <case>.bin there; the message is the txtpb's `# proto-message:` line;
#   3. build every *_roundtrip.goose there with `goose build --debug` and run
#      it (not *_test.goose, which scripts/goose_tests.sh would pick up).
#      It passes iff it exits 0. Tests embed the .bin files (embed_file).
# Exits nonzero if any step fails for any name.
#
# Env: PLUGIN     plugin binary (default: zig build, generator/zig-out/bin)
#      PROTO_DIR     protos     (default tests/protos)
#      ROUNDTRIP_DIR test cases (default tests/roundtrip)
#      PROTOC, GOOSE (default protoc, goose; .tools/bin first)
#      TEST_TIMEOUT  seconds per test (default 120)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
limit="${TEST_TIMEOUT:-120}"
proto_dir="${PROTO_DIR:-$root/tests/protos}"
rt_dir="${ROUNDTRIP_DIR:-$root/tests/roundtrip}"

if [ -z "${PLUGIN:-}" ]; then
  (cd "$root/generator" && zig build) || { echo "error: zig build failed" >&2; exit 1; }
  PLUGIN="$root/generator/zig-out/bin/protoc-gen-goose"
fi

names=()
if [ $# -gt 0 ]; then
  names=("$@")
else
  for d in "$rt_dir"/*/; do [ -d "$d" ] && names+=("$(basename "$d")"); done
fi
[ ${#names[@]} -gt 0 ] || { echo "error: no round-trip tests" >&2; exit 1; }

runner=env  # macOS has no timeout(1)
command -v timeout >/dev/null && runner="timeout $limit"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failed=()
for name in "${names[@]}"; do
  src="$rt_dir/$name"
  proto="$proto_dir/$name.proto"
  work="$tmp/$name"
  fail() { echo "FAIL $name: $*"; failed+=("$name"); }
  [ -d "$src" ] || { fail "no directory $src"; continue; }
  [ -f "$proto" ] || { fail "no $proto"; continue; }
  mkdir -p "$work"
  cp "$src"/* "$work"/
  cp "$root/runtime/pb_wire.goose" "$work"/
  closure=()
  while IFS= read -r i; do closure+=("$i"); done \
    < <("$root/scripts/proto_closure.sh" -I "$proto_dir" "$proto" 2>"$work/log")
  if [ ${#closure[@]} -eq 0 ]; then
    fail "protoc failed"; sed 's/^/    /' "$work/log"; continue
  fi
  if ! "$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$work" \
      -I "$proto_dir" "${closure[@]}" 2>"$work/log"; then
    fail "protoc failed"; sed 's/^/    /' "$work/log"; continue
  fi

  ok=1
  for case in "$work"/*.txtpb; do
    [ -f "$case" ] || continue
    msg="$(sed -n 's/^# proto-message: *//p' "$case" | head -1)"
    stem="$(basename "$case" .txtpb)"
    if [ -z "$msg" ]; then fail "$stem.txtpb has no '# proto-message:' line"; ok=0; break; fi
    if ! "$protoc" --encode="$msg" -I "$proto_dir" "$proto" \
        <"$case" >"$work/$stem.bin" 2>"$work/log"; then
      fail "protoc --encode failed for $stem.txtpb"; sed 's/^/    /' "$work/log"; ok=0; break
    fi
  done
  [ $ok -eq 1 ] || continue

  tests=0
  for t in "$work"/*_roundtrip.goose; do
    [ -f "$t" ] || continue
    tests=$((tests + 1))
    tname="$(basename "$t")"
    if ! (cd "$work" && "$goose" build "$tname" --debug -o "$work/test.bin.exe") >"$work/log" 2>&1; then
      fail "$tname: build failed"
      grep -v '^parsed ok\|^typechecked ok\|^bce:\|^wrote \|^built ' "$work/log" | sed 's/^/    /'
      ok=0; continue
    fi
    if ! $runner "$work/test.bin.exe" >"$work/log" 2>&1; then
      fail "$tname: exited nonzero"; sed 's/^/    /' "$work/log"; ok=0; continue
    fi
  done
  [ $tests -gt 0 ] || { fail "no *_roundtrip.goose"; continue; }
  [ $ok -eq 1 ] && echo "ok   $name"
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "roundtrip: ${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
echo "roundtrip: ${#names[@]} ok"
