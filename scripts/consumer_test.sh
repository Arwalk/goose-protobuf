#!/usr/bin/env bash
# Consumes this repository as a user's project would, from outside it, in a clean
# GOOSE_HOME: installs the plugin, generates a program of two proto files with a
# well-known type, and builds and runs it against each way of getting the runtime
# (a vendored copy, a path, a git tag, a git commit). The repository is a snapshot of
# the tracked files as they are now, with the real .gitmodules and submodule entry.
# Git may use only file://, so nothing touches the network, and a package that would
# fetch the protobuf submodule fails.
# Usage: scripts/consumer_test.sh
# Env: CONSUMER_MUTATE (shell code run in the snapshot before it is committed, for
#      scripts/test_consumer_test.sh)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GOOSE_HOME="$tmp/goose_home" GIT_ALLOW_PROTOCOL=file
git_c=(git -c user.name=consumer -c user.email=consumer@example.com -c commit.gpgsign=false)

bad=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; [ -z "${2:-}" ] || sed 's/^/    /' "$2"; bad=1; }

# The snapshot, as ../goose-protobuf from each consumer.
pub="$tmp/goose-protobuf"
mkdir "$pub"
(cd "$root" && git ls-files -co --exclude-standard -z -- ':!third_party/protobuf') |
  while IFS= read -r -d '' f; do
    [ -e "$root/$f" ] || continue
    mkdir -p "$pub/$(dirname "$f")"; cp -P "$root/$f" "$pub/$f"
  done
submodule="$(git -C "$root" rev-parse HEAD:third_party/protobuf)"
# A package's unimported files must cost nothing, even a broken one (decision 0015).
printf 'extern fn consumer_no_such_symbol(x: i32) -> i32;\nfn broken( {\n' \
  > "$pub/tests/consumer_planted.goose"
if [ -n "${CONSUMER_MUTATE:-}" ]; then (cd "$pub" && eval "$CONSUMER_MUTATE"); fi
if ! ( cd "$pub" && git init -q -b main . && "${git_c[@]}" add -A \
    && git update-index --add --cacheinfo "160000,$submodule,third_party/protobuf" \
    && "${git_c[@]}" commit -qm snapshot && git tag v1.2.3 \
    && git clone -q --bare . "$tmp/goose-protobuf.git" ) >"$tmp/log" 2>&1; then
  fail "snapshot the repository" "$tmp/log"; exit 1
fi
commit="$(git -C "$pub" rev-parse HEAD)"

# The plugin, from the snapshot, found by protoc on PATH.
mkdir "$tmp/prefix"
if "$pub/scripts/install_plugin.sh" "$tmp/prefix" >"$tmp/log" 2>&1; then
  pass "the plugin builds and installs from a fresh copy"
else
  fail "the plugin builds and installs from a fresh copy" "$tmp/log"; exit 1
fi
export PATH="$tmp/prefix/bin:$PATH"

mkdir "$tmp/gen"
cat > "$tmp/gen/item.proto" <<'PROTO'
syntax = "proto3";
package shop;
message Item { string name = 1; }
PROTO
cat > "$tmp/gen/order.proto" <<'PROTO'
syntax = "proto3";
package shop;
import "item.proto";
import "google/protobuf/duration.proto";
message Order { Item item = 1; google.protobuf.Duration wait = 2; }
PROTO
if ! (cd "$tmp/gen" && protoc --goose_out=. item.proto order.proto) >"$tmp/log" 2>&1; then
  fail "protoc generates with no --plugin" "$tmp/log"; exit 1
fi

# consumer <name> <first line of the root file>: a new project next to the snapshot.
consumer() {
  mkdir "$tmp/$1"
  cp "$tmp/gen/"*.goose "$tmp/$1/"
  cat > "$tmp/$1/app.goose" <<APP
$2
import order;

fn main() {
    var o = shop::Order { .. };
    shop::Item_set_name(shop::Order_mutable_item(o), "tea");
    shop::Order_mutable_wait(o).seconds = 7;
    var bytes: u8[>..] = [];
    shop::Order_encode(o, bytes);
    var b = shop::Order { .. };
    if shop::Order_decode(bytes, b) != PB_OK { abort("decode"); }
    let item .= shop::Order_item(b);
    guard item else { abort("no item"); }
    print(shop::Item_name(item), " ", shop::Order_mutable_wait(b).seconds);
}
APP
}
run_app() { (cd "$tmp/$1" && goose build app.goose -o app && ./app) >"$tmp/log" 2>&1 \
  && [ "$(tail -n 1 "$tmp/log")" = "tea 7" ]; }
vendor() { "$pub/scripts/vendor_runtime.sh" "$tmp/$1" >>"$tmp/log" 2>&1; }
builds() {  # builds <name> <description>: the project has been made
  if run_app "$1"; then pass "$2"; else fail "$2" "$tmp/log"; fi
}
rejects() {  # rejects <name> <pattern> <description>
  if (cd "$tmp/$1" && goose check app.goose) >"$tmp/log" 2>&1; then fail "$3: it built"
  elif grep -q -e "$2" "$tmp/log"; then pass "$3"
  else fail "$3" "$tmp/log"; fi
}

consumer path 'import pb_wire from "../goose-protobuf";'
builds path "a path to a checkout"

consumer vendored 'import pb_wire;'
: >"$tmp/log"; vendor vendored
builds vendored "a vendored copy"

git_source="file://$tmp/goose-protobuf.git"
consumer tag "import pb_wire from \"$git_source@v1.2.3\";"
builds tag "a git source at a tag"
if (cd "$tmp/tag" && goose run app.goose) >"$tmp/log" 2>&1 && [ "$(tail -n 1 "$tmp/log")" = "tea 7" ]; then
  pass "goose run on a git source"
else
  fail "goose run on a git source" "$tmp/log"
fi

consumer commit "import pb_wire from \"$git_source@$commit\";"
builds commit "a git source at a commit"

# Generated code in a directory of its own is a package (decision 0013).
to_gen_package() {  # to_gen_package <name>: moves its generated files to gen/, with an entry
  mkdir "$tmp/$1/gen"
  (cd "$tmp/$1" && for f in *.goose; do [ "$f" = app.goose ] || mv "$f" gen/; done)
  printf 'import .order;\n' > "$tmp/$1/gen/gen.goose"
  sed 's/^import order;$/import gen from ".\/gen";/' "$tmp/$1/app.goose" > "$tmp/$1/app.new"
  mv "$tmp/$1/app.new" "$tmp/$1/app.goose"
}
consumer gen_path 'import pb_wire from "../goose-protobuf";'
to_gen_package gen_path
builds gen_path "generated code in a package of its own, with a path to a checkout"

consumer gen_git "import pb_wire from \"$git_source@v1.2.3\";"
to_gen_package gen_git
builds gen_git "generated code in a package of its own, with a git source"

consumer gen_vendored ''
to_gen_package gen_vendored
: >"$tmp/log"; vendor gen_vendored/gen
builds gen_vendored "generated code in a package of its own, with the runtime vendored into it"

consumer gen_beside 'import pb_wire;'
to_gen_package gen_beside
: >"$tmp/log"; vendor gen_beside
rejects gen_beside 'cannot find the module pb_wire' "a runtime vendored beside the root does not reach a package"

# What a git source fetched: the package, without the protobuf submodule.
fetched=("$GOOSE_HOME"/pkg/goose-protobuf-*/v1.2.3)
if [ -f "${fetched[0]}/pb_wire.goose" ] && [ -z "$(ls -A "${fetched[0]}/third_party/protobuf" 2>/dev/null)" ]; then
  pass "the package leaves the protobuf submodule out"
else
  fail "the package leaves the protobuf submodule out"
fi
max_fetch_kb=20480
fetch_kb="$(du -sk "${fetched[0]}" | cut -f1)"
if [ "$fetch_kb" -le "$max_fetch_kb" ]; then
  pass "the fetched package stays small ($fetch_kb KB)"
else
  fail "the fetched package stays small: $fetch_kb KB, over $max_fetch_kb KB (decision 0015)"
fi

# A runtime of another version: as this one, with its version name changed.
consumer mismatch 'import pb_wire;'
: >"$tmp/log"; vendor mismatch
sed 's/_abi_[0-9]*/_abi_999/' "$tmp/mismatch/pb_wire.goose" > "$tmp/mismatch/pb_wire.new"
mv "$tmp/mismatch/pb_wire.new" "$tmp/mismatch/pb_wire.goose"
rejects mismatch 'unknown identifier: pb_plugin_and_runtime_versions_differ_abi_' \
  "a runtime of another version does not build, and the name says why"

# Files whose output paths are alike share the global namespace, and must not share
# the name of their version check.
consumer alike 'import pb_wire from "../goose-protobuf";'
mkdir -p "$tmp/alike_gen/a"
printf 'syntax = "proto3";\nmessage InPath { int32 n = 1; }\n' > "$tmp/alike_gen/a/b.proto"
printf 'syntax = "proto3";\nmessage InName { int32 n = 1; }\n' > "$tmp/alike_gen/a_b.proto"
(cd "$tmp/alike_gen" && protoc --goose_out="$tmp/alike" a/b.proto a_b.proto) >"$tmp/log" 2>&1
printf 'import a.b;\nimport a_b;\n' >> "$tmp/alike/app.goose"
builds alike "generated files with alike paths build together"

consumer missing '// no pb_wire'
rejects missing 'cannot find the module pb_wire' "no runtime is a clear error"

consumer both 'import pb_wire from "../goose-protobuf";'
: >"$tmp/log"; vendor both
rejects both 'both a file of this package' "a vendored copy and a package together are a clear error"

exit $bad
