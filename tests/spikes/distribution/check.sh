#!/usr/bin/env bash
# Spike gpb-wof.5: how a project outside this repo gets pb_wire
# (docs/decisions/0005-runtime-distribution.md). Builds and runs a consumer of
# generated code for each way that should work, and checks the ones that
# should not. Works in a temp dir, with its own GOOSE_HOME and only local git
# repositories, so it needs no network and leaves ~/.goose alone.
# Usage: tests/spikes/distribution/check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
(cd "$root/generator" && zig build)
plugin="$root/generator/zig-out/bin/protoc-gen-goose"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GOOSE_HOME="$tmp/goose_home"
# Local submodules, which real (https) ones do not need.
export GIT_ALLOW_PROTOCOL=file
git_c=(git -c user.name=spike -c user.email=spike@example.com -c protocol.file.allow=always)
bad=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; bad=1; }

mkdir "$tmp/gen"
cat > "$tmp/gen/sample.proto" <<'PROTO'
syntax = "proto3";
package sample;
message Msg { int32 n = 1; string s = 2; }
PROTO
protoc --plugin=protoc-gen-goose="$plugin" --goose_out="$tmp/gen" -I "$tmp/gen" sample.proto
grep -q '^import pb_wire;$' "$tmp/gen/sample.goose" || fail "generated code imports pb_wire by name"

# consumer <dir> <first line of the root file> [where sample.goose goes]
consumer() {
  local module="${3:-sample}"
  mkdir -p "$1/$(dirname "${module//.//}")"
  cp "$tmp/gen/sample.goose" "$1/${module//.//}.goose"
  cat > "$1/app.goose" <<APP
$2
import $module;
fn main() {
    var m = sample::Msg { .. };
    m.n = 7;
    sample::Msg_set_s(m, "hi");
    var out: u8[>..] = [];
    sample::Msg_encode(m, out);
    var b = sample::Msg { .. };
    if sample::Msg_decode(out, b) != PB_OK || b.n != 7 { abort("round trip"); }
    print("ok");
}
APP
}
builds() {  # builds <dir> <description>
  if (cd "$1" && goose build app.goose -o app.exe && ./app.exe) >"$tmp/log" 2>&1 \
      && grep -q '^ok$' "$tmp/log"; then pass "$2"
  else fail "$2"; sed 's/^/    /' "$tmp/log"; fi
}
rejects() {  # rejects <dir> <grep pattern> <description>
  if (cd "$1" && goose check app.goose) >"$tmp/log" 2>&1; then fail "$3: it built"
  elif grep -q -e "$2" "$tmp/log"; then pass "$3"
  else fail "$3"; sed 's/^/    /' "$tmp/log"; fi
}
# repo <dir> <tag>: commits what is in dir, tags it, and clones it bare to dir.git.
repo() {
  (cd "$1" && git init -q -b main . 2>/dev/null; "${git_c[@]}" add -A \
    && "${git_c[@]}" commit -qm commit && "${git_c[@]}" tag "$2")
  rm -rf "$1.git"; git clone -q --bare "$1" "$1.git"
}

# A vendored copy next to the program.
mkdir "$tmp/vendored"; cp "$root/runtime/pb_wire.goose" "$tmp/vendored/"
consumer "$tmp/vendored" "import pb_wire;"
builds "$tmp/vendored" "a vendored copy"

# A local path, to this repo's runtime directory.
mkdir "$tmp/local"
consumer "$tmp/local" "import pb_wire from \"$(realpath --relative-to="$tmp/local" "$root/runtime")\";"
builds "$tmp/local" "a local path package"

# A git URL, with the entry at the root of a repository of its own.
mkdir "$tmp/own"; cp "$root/runtime/pb_wire.goose" "$tmp/own/"; repo "$tmp/own" v1
mkdir "$tmp/git"; consumer "$tmp/git" "import pb_wire from \"file://$tmp/own.git@v1\";"
builds "$tmp/git" "a git URL, entry at the root of its own repository"

# The same, with the generated file in a directory of the program.
mkdir "$tmp/subdir"; consumer "$tmp/subdir" "import pb_wire from \"file://$tmp/own.git@v1\";" gen.sample
builds "$tmp/subdir" "a git URL, generated code in a subdirectory"

# This repo's layout: the entry only in runtime/. Not a package as it is...
mkdir -p "$tmp/mono/runtime"; cp "$root/runtime/pb_wire.goose" "$tmp/mono/runtime/"
# ...and other .goose files of the tree, even invalid ones, do no harm.
mkdir "$tmp/mono/tests"; echo 'this is not goose' > "$tmp/mono/tests/junk.goose"
repo "$tmp/mono" v1
mkdir "$tmp/no_entry"; consumer "$tmp/no_entry" "import pb_wire from \"file://$tmp/mono.git@v1\";"
rejects "$tmp/no_entry" 'has no pb_wire.goose' "a repository without a root entry is rejected"

# A git source cannot name a subdirectory.
mkdir "$tmp/sub_src"; consumer "$tmp/sub_src" "import pb_wire from \"file://$tmp/mono.git/runtime@v1\";"
rejects "$tmp/sub_src" 'cannot fetch' "a subdirectory in a git source is rejected"

# A one-line root entry makes this repo's layout a package.
printf '// Package entry.\nimport .runtime.pb_wire;\n' > "$tmp/mono/pb_wire.goose"
repo "$tmp/mono" v2
mkdir "$tmp/shim"; consumer "$tmp/shim" "import pb_wire from \"file://$tmp/mono.git@v2\";"
builds "$tmp/shim" "a git URL, one-line root entry over runtime/"

# Fetching clones submodules, this repo's protobuf too, unless they are
# marked update = none.
mkdir "$tmp/big"; echo payload > "$tmp/big/payload.txt"; repo "$tmp/big" v1
fetched_submodule() {  # fetched_submodule <repo name>: 0 if its submodule came along
  ls -d "$GOOSE_HOME"/pkg/"$1"-*/v1/third_party/big/payload.txt >/dev/null 2>&1
}
for mode in plain none; do
  d="$tmp/sm_$mode"; mkdir -p "$d/runtime"
  cp "$root/runtime/pb_wire.goose" "$d/runtime/"
  printf 'import .runtime.pb_wire;\n' > "$d/pb_wire.goose"
  (cd "$d" && git init -q -b main . 2>/dev/null \
    && "${git_c[@]}" submodule --quiet add "$tmp/big.git" third_party/big)
  [ $mode = none ] && git -C "$d" config -f .gitmodules submodule.third_party/big.update none
  repo "$d" v1
  c="$tmp/cons_$mode"; mkdir "$c"; consumer "$c" "import pb_wire from \"file://$d.git@v1\";"
  builds "$c" "a git URL, repository with a submodule ($mode)"
done
fetched_submodule sm_plain && pass "a plain submodule is fetched with the package" || fail "a plain submodule is fetched with the package"
fetched_submodule sm_none && fail "update = none keeps a submodule out" || pass "update = none keeps a submodule out"

# Nothing to resolve the name: a clear error.
mkdir "$tmp/missing"; consumer "$tmp/missing" "// no pb_wire"
rejects "$tmp/missing" 'cannot find the module pb_wire' "no runtime is a clear error"

# A vendored copy and a declared package together: a clear error.
mkdir "$tmp/both"; cp "$root/runtime/pb_wire.goose" "$tmp/both/"
consumer "$tmp/both" "import pb_wire from \"file://$tmp/own.git@v1\";"
rejects "$tmp/both" 'both a file of this package' "a vendored copy and a package together are an error"

exit $bad
