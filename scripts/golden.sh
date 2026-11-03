#!/usr/bin/env bash
# Golden tests for protoc-gen-goose.
# Usage: scripts/golden.sh [--update]
#
# For each tests/protos/<name>.proto:
#   1. run protoc with the plugin twice, into two temp dirs, and require
#      byte-identical output (Goose has no formatter, so the generator must
#      be deterministic);
#   2. diff the output against tests/golden/<name>/ (a missing directory
#      means "no files"); --update rewrites tests/golden/<name>/ instead;
#   3. `goose check` every .goose file in tests/golden/<name>/. Goose has no
#      include path, so each file is checked from a directory holding a copy
#      of the golden tree plus runtime/pb_wire.goose (`import pb_wire;`).
# Exits nonzero if any proto fails any step; all failures are reported.
#
# Env: PLUGIN     plugin binary (default: zig build, generator/zig-out/bin)
#      PROTO_DIR  input protos   (default tests/protos)
#      GOLDEN_DIR golden tree    (default tests/golden)
#      PROTOC, GOOSE             (default protoc, goose; .tools/bin first)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
proto_dir="${PROTO_DIR:-$root/tests/protos}"
golden_dir="${GOLDEN_DIR:-$root/tests/golden}"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"

update=0
case "${1:-}" in
  "") ;;
  --update) update=1 ;;
  *) echo "usage: $0 [--update]" >&2; exit 2 ;;
esac

if [ -z "${PLUGIN:-}" ]; then
  (cd "$root/generator" && zig build) || { echo "error: zig build failed" >&2; exit 1; }
  PLUGIN="$root/generator/zig-out/bin/protoc-gen-goose"
fi
[ -x "$PLUGIN" ] || { echo "error: plugin $PLUGIN not executable" >&2; exit 1; }

includes=(-I "$proto_dir")
wkt="$(ls -d "$root"/.tools/protoc-*/include 2>/dev/null | head -1)"
[ -n "$wkt" ] && includes+=(-I "$wkt")

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failed=()

gen() {  # gen <proto> <outdir>
  mkdir -p "$2"
  "$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$2" \
    "${includes[@]}" "$1"
}

shopt -s nullglob
protos=("$proto_dir"/*.proto)
[ ${#protos[@]} -gt 0 ] || { echo "error: no .proto files in $proto_dir" >&2; exit 1; }

for proto in "${protos[@]}"; do
  name="$(basename "$proto" .proto)"
  a="$tmp/$name/a"; b="$tmp/$name/b"; golden="$golden_dir/$name"
  ok=1

  if ! gen "$proto" "$a" || ! gen "$proto" "$b"; then
    echo "FAIL $name: protoc/plugin failed"; failed+=("$name"); continue
  fi
  if ! diff -r "$a" "$b" >"$tmp/$name/nondet" 2>&1; then
    echo "FAIL $name: output differs between two runs (nondeterministic)"
    cat "$tmp/$name/nondet"; ok=0
  fi

  if [ $update = 1 ]; then
    rm -rf "$golden"
    if [ -n "$(ls -A "$a")" ]; then mkdir -p "$golden" && cp -R "$a/." "$golden/"; fi
  else
    golden_cmp="$golden"
    if [ ! -d "$golden" ]; then golden_cmp="$tmp/$name/empty"; mkdir -p "$golden_cmp"; fi
    if ! diff -ruN "$golden_cmp" "$a" >"$tmp/$name/diff" 2>&1; then
      # Show tree-relative paths instead of temp dirs.
      echo "FAIL $name: generated output differs from tests/golden/$name"
      sed -e "s#$golden_cmp#golden/$name#g" -e "s#$a#generated/$name#g" \
        "$tmp/$name/diff"
      echo "  (run scripts/golden.sh --update to accept)"
      ok=0
    fi
  fi

  if [ -d "$golden" ]; then
    chk="$tmp/$name/check"; mkdir -p "$chk"
    cp -R "$golden/." "$chk/"
    cp "$root/runtime/pb_wire.goose" "$chk/pb_wire.goose"
    while IFS= read -r -d '' f; do
      rel="${f#$golden/}"
      if ! (cd "$chk" && "$goose" check "$rel") >"$tmp/$name/check.log" 2>&1; then
        echo "FAIL $name: goose check failed on tests/golden/$name/$rel"
        grep -v '^parsed ok\|^typechecked ok\|^bce:' "$tmp/$name/check.log"
        ok=0
      fi
    done < <(find "$golden" -name '*.goose' -type f -print0 | sort -z)
  fi

  if [ $ok = 1 ]; then echo "ok   $name"; else failed+=("$name"); fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "golden: ${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
echo "golden: ${#protos[@]} ok"
