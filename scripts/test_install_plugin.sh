#!/usr/bin/env bash
# Self-test for scripts/install_plugin.sh: once installed, protoc finds the plugin
# on PATH with no --plugin, and writes what the golden test expects. protoc runs
# from a directory holding nothing else, so nothing but the install can provide it.
# Usage: scripts/test_install_plugin.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
install="$root/scripts/install_plugin.sh"
protos="$root/tests/protos"
golden="$root/tests/golden/smoke/smoke.goose"

mkdir "$tmp/tools"
ln -s "$(command -v protoc)" "$tmp/tools/protoc"
base="$tmp/tools:/usr/bin:/bin"

bad=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; [ -z "${2:-}" ] || cat "$2"; bad=1; }

# protoc_on <PATH> runs protoc in a new directory; the output lands in $tmp/out.
protoc_on() {
  rm -rf "$tmp/out"; mkdir "$tmp/out"
  (cd "$tmp/out" && PATH="$1" protoc --goose_out=. -I "$protos" smoke.proto) >"$tmp/log" 2>&1
}

if protoc_on "$base"; then
  fail "protoc fails before the install (is one on the system PATH?)"
else
  grep -q 'protoc-gen-goose' "$tmp/log" && pass "protoc fails before the install" \
    || fail "protoc fails naming the plugin" "$tmp/log"
fi

if "$install" "$tmp/pre fix" >"$tmp/out.log" 2>"$tmp/err.log"; then
  pass "installs into a prefix with a space in it"
else
  fail "installs into a prefix with a space in it" "$tmp/err.log"
fi
[ -x "$tmp/pre fix/bin/protoc-gen-goose" ] && pass "the binary is executable" \
  || fail "the binary is executable"
[ -f "$tmp/pre fix/bin/protoc-gen-goose" ] && [ ! -L "$tmp/pre fix/bin/protoc-gen-goose" ] && pass "it is a copy, which outlives the checkout" \
  || fail "it is a copy, which outlives the checkout"
grep -qF "$tmp/pre fix/bin/protoc-gen-goose" "$tmp/out.log" && pass "stdout names the installed path" \
  || fail "stdout names the installed path" "$tmp/out.log"

if protoc_on "$tmp/pre fix/bin:$base"; then
  if cmp -s "$tmp/out/smoke.goose" "$golden"; then
    pass "protoc finds it on PATH and writes the golden output"
  else
    fail "protoc finds it on PATH and writes the golden output: output differs"
  fi
else
  fail "protoc finds it on PATH" "$tmp/log"
fi

"$install" "$tmp/pre fix" >/dev/null 2>"$tmp/err.log" && pass "installing again succeeds" \
  || fail "installing again succeeds" "$tmp/err.log"

mkdir "$tmp/cwd"
(cd "$tmp/cwd" && "$install" rel >/dev/null 2>"$tmp/err.log") && [ -x "$tmp/cwd/rel/bin/protoc-gen-goose" ] \
  && pass "a relative prefix is relative to the current directory" \
  || fail "a relative prefix is relative to the current directory" "$tmp/err.log"

mkdir "$tmp/home"
HOME="$tmp/home" "$install" >/dev/null 2>&1
[ -x "$tmp/home/.local/bin/protoc-gen-goose" ] && pass "the default prefix is ~/.local" \
  || fail "the default prefix is ~/.local"

PATH="$base" GOOSE="$(command -v goose)" "$install" "$tmp/pre fix" >/dev/null 2>"$tmp/err.log"
grep -q 'not on PATH' "$tmp/err.log" && pass "it warns when the directory is not on PATH" \
  || fail "it warns when the directory is not on PATH" "$tmp/err.log"

PATH="$tmp/pre fix/bin:$base" GOOSE="$(command -v goose)" "$install" "$tmp/pre fix" >/dev/null 2>"$tmp/err.log"
[ ! -s "$tmp/err.log" ] && pass "it is silent on stderr when the directory is on PATH" \
  || fail "it is silent on stderr when the directory is on PATH" "$tmp/err.log"

exit $bad
