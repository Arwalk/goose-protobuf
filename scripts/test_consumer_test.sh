#!/usr/bin/env bash
# Self-test for scripts/consumer_test.sh: the repository as it is passes, and each
# way of breaking what consumers rely on fails, at the check that should catch it.
# Usage: scripts/test_consumer_test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bad=0
case_() {  # case_ <want-exit> <mutation> <pattern> <description>
  local out status
  out="$(CONSUMER_MUTATE="$2" "$root/scripts/consumer_test.sh" 2>&1)"; status=$?
  if [ $status = "$1" ] && grep -q -e "$3" <<<"$out"; then
    echo "PASS $4"
  else
    echo "FAIL $4: exit $status"; echo "$out"; bad=1
  fi
}
case_ 0 ':' '^PASS a git source at a commit' "the repository as it is passes"
case_ 1 'rm pb_wire.goose' '^FAIL a git source at a tag' "no package entry at the root"
case_ 1 'rm wkt/duration.goose' '^FAIL a path to a checkout' "a well-known type missing"
case_ 1 'rm -r wkt' '^FAIL the plugin builds' "no well-known types"
case_ 1 "git config -f .gitmodules --unset submodule.third_party/protobuf.update" \
  '^FAIL a git source at a tag' "a package that would fetch its submodule"
case_ 1 'head -c 30000000 /dev/urandom > tests/big' \
  '^FAIL the fetched package stays small' "a package grown too large"
case_ 1 'echo "import .tests.consumer_planted;" >> pb_wire.goose' \
  '^FAIL a path to a checkout' "a package that compiles a broken file"
case_ 1 'rm scripts/install_plugin.sh' '^FAIL the plugin builds' "no install script"
exit $bad
