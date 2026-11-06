#!/usr/bin/env bash
# Compares the self-hosted plugin, build/protoc-gen-goose-self, with the Zig one:
# their output must be byte-identical. For each tests/protos/<name>.proto, as
# scripts/golden.sh does, the file alone and with its import closure; the
# well-known types with the `wkt` parameter (scripts/wkt.sh); the conformance
# protos of scripts/build_testee.sh, when the submodule is checked out; the
# plugin's own bindings; and whole
# responses, byte for byte, for requests protoc makes and for those the plugin must
# reject. Every file the self-hosted plugin writes then goes through `goose check`,
# failing on warnings too, unless --no-check is given.
# Usage: scripts/selfhost_diff.sh [--no-check] [names]
#   names: protos of tests/protos, or wkt, conformance, plugin, responses (default: all)
# Exits nonzero on any difference or failed check.
# Env: PLUGIN (default: zig build), SELF (default: scripts/build_selfhost.sh),
#      PROTOC, GOOSE (default protoc, goose; .tools/bin first)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
protoc="${PROTOC:-protoc}"
goose="${GOOSE:-goose}"
proto_dir="$root/tests/protos"
check=1
if [ "${1:-}" = "--no-check" ]; then check=0; shift; fi
names=("$@")

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  PLUGIN="$root/build/protoc-gen-goose"
fi
if [ -z "${SELF:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  SELF="$root/build/protoc-gen-goose"
fi

includes=(-I "$proto_dir")
wkt_inc="$(ls -d "$root"/.tools/protoc-*/include 2>/dev/null | head -1)"
[ -n "$wkt_inc" ] && includes+=(-I "$wkt_inc")

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
same=0 failed=()

wanted() {  # wanted <name>: true if no names were given, or this is one of them
  [ ${#names[@]} -eq 0 ] && return 0
  local n
  for n in "${names[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

fail() { echo "FAIL $1"; failed+=("$1"); }

# gen_both <what> <out option prefix> <protoc args...>: into $tmp/zig and $tmp/self.
# Returns 1 if protoc fails with either plugin; the two must fail alike.
gen_both() {
  local prefix="$1"; shift
  rm -rf "$tmp/zig" "$tmp/self"; mkdir -p "$tmp/zig" "$tmp/self"
  local zs=0 ss=0
  "$protoc" --plugin=protoc-gen-goose="$PLUGIN" --goose_out="$prefix$tmp/zig" "$@" 2>"$tmp/zig.err" || zs=$?
  "$protoc" --plugin=protoc-gen-goose="$SELF" --goose_out="$prefix$tmp/self" "$@" 2>"$tmp/self.err" || ss=$?
  [ $zs = 0 ] && [ $ss = 0 ] && return 0
  echo "  protoc exit: zig $zs, self $ss"
  sed 's/^/  zig:  /' "$tmp/zig.err"
  sed 's/^/  self: /' "$tmp/self.err"
  return 1
}

# compare <what>: diffs $tmp/zig and $tmp/self, with an excerpt on a mismatch.
compare() {
  if diff -ruN "$tmp/zig" "$tmp/self" >"$tmp/diff"; then
    echo "identical $1 ($(find "$tmp/zig" -type f | wc -l) files)"
    same=$((same + 1))
    return 0
  fi
  fail "$1: output differs ($(grep -c '^[-+][^-+]' "$tmp/diff") lines)"
  sed -e "s#$tmp/zig#zig#g" -e "s#$tmp/self#self#g" "$tmp/diff" | head -40 | sed 's/^/    /'
  return 1
}

# check_self <what>: `goose check` of every file in $tmp/self, failing on warnings
# too. Goose resolves imports from the root file's directory, so the root is a file
# at the top of the tree, next to the runtime, that imports the one to check.
check_self() {
  [ $check = 1 ] || return 0
  "$root/scripts/vendor_runtime.sh" "$tmp/self"
  local f rel mod
  while IFS= read -r f; do
    rel="${f#"$tmp"/self/}"
    case "$rel" in pb_wire.goose|pb_wire/*|check_root.goose) continue ;; esac
    mod="${rel%.goose}"
    echo "import ${mod//\//.};" >"$tmp/self/check_root.goose"
    if ! (cd "$tmp/self" && "$goose" check check_root.goose) >"$tmp/check.log" 2>&1; then
      fail "$1: goose check failed on $rel"
      grep -v '^parsed ok\|^typechecked ok\|^bce:' "$tmp/check.log" | head -20 | sed 's/^/    /'
    elif grep -q 'warning:' "$tmp/check.log"; then
      fail "$1: goose check warned on $rel"
      grep 'warning:' "$tmp/check.log" | head -20 | sed 's/^/    /'
    fi
  done < <(find "$tmp/self" -name '*.goose' -type f | LC_ALL=C sort)
}

shopt -s nullglob
for proto in "$proto_dir"/*.proto; do
  name="$(basename "$proto" .proto)"
  wanted "$name" || continue
  if gen_both "" "${includes[@]}" "$proto"; then
    compare "$name"
  else
    fail "$name: protoc failed"
    continue
  fi
  closure=()
  while IFS= read -r i; do closure+=("$i"); done \
    < <("$root/scripts/proto_closure.sh" "${includes[@]}" "$proto")
  if gen_both "" "${includes[@]}" "${closure[@]}"; then
    compare "$name+imports" && check_self "$name"
  else
    fail "$name+imports: protoc failed"
  fi
done

if wanted wkt; then
  if gen_both "wkt:" -I "$wkt_inc" \
      google/protobuf/any.proto google/protobuf/duration.proto \
      google/protobuf/empty.proto google/protobuf/field_mask.proto \
      google/protobuf/struct.proto google/protobuf/timestamp.proto \
      google/protobuf/wrappers.proto; then
    compare wkt
    if [ -d "$tmp/self/wkt" ] && ! diff -ruN "$root/wkt" "$tmp/self/wkt" >"$tmp/diff"; then
      fail "wkt: differs from the committed wkt/"
      head -40 "$tmp/diff" | sed 's/^/    /'
    fi
    if [ $check = 1 ]; then
      mkdir "$tmp/chk"
      "$root/scripts/vendor_runtime.sh" "$tmp/chk"
      for f in "$tmp"/self/wkt/*.goose; do
        mod="$(basename "$f" .goose)"
        echo "import pb_wire.wkt.$mod;" >"$tmp/chk/check_root.goose"
        (cd "$tmp/chk" && "$goose" check check_root.goose) >"$tmp/check.log" 2>&1 ||
          { fail "wkt: goose check failed on $mod"; head -20 "$tmp/check.log" | sed 's/^/    /'; }
      done
    fi
  else
    fail "wkt: protoc failed"
  fi
fi

pb="$root/third_party/protobuf"
if wanted conformance; then
  if [ -f "$pb/src/google/protobuf/test_messages_proto3.proto" ]; then
    closure=()
    while IFS= read -r i; do closure+=("$i"); done \
      < <("$root/scripts/proto_closure.sh" -I "$pb/src" -I "$pb" \
            google/protobuf/test_messages_proto3.proto \
            google/protobuf/test_messages_proto2.proto \
            editions/golden/test_messages_proto3_editions.proto \
            editions/golden/test_messages_proto2_editions.proto \
            conformance/test_protos/test_messages_edition2023.proto | sort -u)
    if gen_both "" -I "$pb/src" -I "$pb" "${closure[@]}"; then
      compare conformance && check_self conformance
    else
      fail "conformance: protoc failed"
    fi
    if gen_both "" -I "$pb" conformance/conformance.proto; then
      compare conformance.proto && check_self conformance.proto
    else
      fail "conformance.proto: protoc failed"
    fi
  else
    echo "skipped conformance: the submodule is not checked out"
  fi
fi

# Its own input: the bindings the self-hosted plugin is built on, which the Zig
# plugin generated, come out the same from the self-hosted one.
if wanted plugin; then
  if gen_both "" "${includes[@]}" google/protobuf/compiler/plugin.proto google/protobuf/descriptor.proto; then
    compare plugin
  else
    fail "plugin: protoc failed"
  fi
fi

# The response to a request, byte for byte, exit status too.
compare_response() {  # compare_response <what> <request file>
  local zs=0 ss=0
  "$PLUGIN" <"$2" >"$tmp/zig.res" 2>/dev/null || zs=$?
  "$SELF" <"$2" >"$tmp/self.res" 2>/dev/null || ss=$?
  if [ $zs != $ss ]; then
    fail "response $1: exit status: zig $zs, self $ss"
  elif ! cmp -s "$tmp/zig.res" "$tmp/self.res"; then
    fail "response $1: $(cmp "$tmp/zig.res" "$tmp/self.res" 2>&1)"
    (cd "$tmp" && strings -n 8 zig.res | head -5 | sed 's/^/    zig:  /'; strings -n 8 self.res | head -5 | sed 's/^/    self: /')
  else
    echo "identical response $1 (exit $zs, $(wc -c <"$tmp/zig.res") bytes)"
    same=$((same + 1))
  fi
}

# capture <out> <protoc args...>: the request protoc sends a plugin. Its reply says
# nothing of editions, which protoc may reject: protoc's status means nothing.
capture() {
  local out="$1"; shift
  cat >"$tmp/dump" <<SH
#!/bin/sh
cat >"$out"
SH
  chmod +x "$tmp/dump"
  rm -f "$out"
  "$protoc" --plugin=protoc-gen-dump="$tmp/dump" "$@" >/dev/null 2>&1
  [ -s "$out" ] || fail "no request captured for $out"
}

if wanted responses; then
  mkdir -p "$tmp/out" "$tmp/bad"
  for proto in "$proto_dir"/*.proto; do
    name="$(basename "$proto" .proto)"
    capture "$tmp/req.bin" --dump_out="$tmp/out" "${includes[@]}" "$proto"
    compare_response "$name" "$tmp/req.bin"
  done
  first="$proto_dir/$(basename "$(ls "$proto_dir"/*.proto | head -1)")"
  capture "$tmp/req.bin" --dump_out=nope:"$tmp/out" "${includes[@]}" "$first"
  compare_response "unknown parameter" "$tmp/req.bin"
  capture "$tmp/req.bin" --dump_out=wkt:"$tmp/out" "${includes[@]}" "$first"
  compare_response "wkt with another file" "$tmp/req.bin"
  capture "$tmp/req.bin" --dump_out="$tmp/out" -I "$wkt_inc" google/protobuf/empty.proto
  compare_response "well-known file, no parameter" "$tmp/req.bin"

  # Input the plugin must reject.
  cat >"$tmp/bad/nested_top.proto" <<'P'
syntax = "proto3";
message A { message B {} }
message A_B {}
P
  cat >"$tmp/bad/enum_value.proto" <<'P'
syntax = "proto3";
enum E { X = 0; }
message E_X {}
P
  cat >"$tmp/bad/generated.proto" <<'P'
syntax = "proto3";
message A { int32 id = 1; }
message A_decode {}
P
  cat >"$tmp/bad/record_field.proto" <<'P'
syntax = "proto2";
message A { optional int32 type = 1; optional int32 type_ = 2; }
P
  cat >"$tmp/bad/accessor.proto" <<'P'
syntax = "proto3";
message A { string x = 1; string set_x = 2; }
P
  cat >"$tmp/bad/imported_bad.proto" <<'P'
syntax = "proto3";
message C { message D {} }
message C_D {}
P
  cat >"$tmp/bad/imports_bad.proto" <<'P'
syntax = "proto3";
import "imported_bad.proto";
message U { C c = 1; }
P
  for n in nested_top enum_value generated record_field accessor imports_bad; do
    capture "$tmp/req.bin" --dump_out="$tmp/out" -I "$tmp/bad" "$n.proto"
    compare_response "collision $n" "$tmp/req.bin"
  done
  printf 'syntax = "proto3";\nmessage A {}\n' >"$tmp/bad/a.b.proto"
  printf 'syntax = "proto3";\nmessage C {}\n' >"$tmp/bad/a-b.proto"
  capture "$tmp/req.bin" --dump_out="$tmp/out" -I "$tmp/bad" a.b.proto a-b.proto
  compare_response "two protos, one output" "$tmp/req.bin"

  # Requests protoc would not make.
  : >"$tmp/empty.bin"
  compare_response "empty request" "$tmp/empty.bin"
  printf '\012\001x' >"$tmp/missing.bin"
  compare_response "file not in proto_file" "$tmp/missing.bin"
  printf '\012\005a' >"$tmp/cut.bin"
  compare_response "truncated request" "$tmp/cut.bin"
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo "selfhost_diff: ${#failed[@]} failed, $same identical"
  exit 1
fi
echo "selfhost_diff: $same identical"
