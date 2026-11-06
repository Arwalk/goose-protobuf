#!/usr/bin/env bash
# Generates each tests/protos/<name>.proto with buf and compares every file with
# tests/golden/<name>/ (a missing directory means "no files"). buf has its own
# compiler, and docs/build-systems.md says the files are the same as protoc's, byte
# for byte, so a change to the generator or to the buf pin must not make them differ.
# Each proto runs alone, as protoc does in scripts/golden.sh: several in tests/protos
# declare the same names, which one buf build refuses.
# Usage: scripts/buf_golden.sh
# Env: PLUGIN     plugin binary (default: scripts/build_plugin.sh)
#      PROTO_DIR  input protos   (default tests/protos)
#      GOLDEN_DIR golden tree    (default tests/golden)
#      BUF        (default buf; .tools/bin first; scripts/install_buf.sh installs it)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
proto_dir="$(cd "${PROTO_DIR:-$root/tests/protos}" && pwd)"
golden_dir="${GOLDEN_DIR:-$root/tests/golden}"
buf="${BUF:-buf}"
command -v "$buf" >/dev/null || { echo "error: buf not found; run scripts/install_buf.sh" >&2; exit 1; }

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  PLUGIN="$root/build/protoc-gen-goose"
fi
[ -x "$PLUGIN" ] || { echo "error: plugin $PLUGIN not executable" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$proto_dir" "$tmp/protos"
cat > "$tmp/buf.yaml" <<YAML
version: v2
modules:
  - path: protos
YAML
cat > "$tmp/buf.gen.yaml" <<YAML
version: v2
plugins:
  - local: $PLUGIN
    out: out
YAML

shopt -s nullglob
protos=("$tmp"/protos/*.proto)
[ ${#protos[@]} -gt 0 ] || { echo "error: no .proto files in $proto_dir" >&2; exit 1; }

failed=()
files=0
for proto in "${protos[@]}"; do
  name="$(basename "$proto" .proto)"
  golden="$golden_dir/$name"
  rm -rf "$tmp/out"; mkdir -p "$tmp/out" "$tmp/empty"
  if ! (cd "$tmp" && "$buf" generate --path "protos/$name.proto") >"$tmp/log" 2>&1; then
    echo "FAIL $name: buf generate failed"; cat "$tmp/log"; failed+=("$name"); continue
  fi
  want="$golden"
  [ -d "$golden" ] || want="$tmp/empty"
  if diff -ruN "$want" "$tmp/out" >"$tmp/diff" 2>&1; then
    echo "ok   $name"
    files=$((files + $(find "$tmp/out" -type f | wc -l)))
  else
    echo "FAIL $name: buf's output differs from tests/golden/$name"
    sed -e "s#$want#golden/$name#g" -e "s#$tmp/out#buf/$name#g" "$tmp/diff"
    failed+=("$name")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "buf_golden: ${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
if [ "$files" = 0 ]; then
  echo "error: buf generated nothing, so nothing was compared" >&2
  exit 1
fi
echo "buf_golden: ${#protos[@]} protos, $files files identical"
