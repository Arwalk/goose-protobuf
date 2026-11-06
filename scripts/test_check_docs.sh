#!/usr/bin/env bash
# Self-test for scripts/check_docs.py on scripts/testdata/check_docs/: a good
# guide passes; a snippet that does not compile, wrong output, a block with no
# label, and blocks no command uses all fail. A guide runs with a home of its own.
# Usage: scripts/test_check_docs.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
data="$root/scripts/testdata/check_docs"
bad=0
case_() {  # case_ <file> <want-exit> <pattern> <description>
  local out status
  out="$(python3 "$root/scripts/check_docs.py" "$data/$1" 2>&1)"; status=$?
  if [ $status = "$2" ] && grep -q -e "$3" <<<"$out"; then echo "PASS $4"
  else echo "FAIL $4: exit $status"; echo "$out"; bad=1; fi
}
export REAL_HOME="$HOME"
case_ home.md       0 '^ok '                 "a guide has its own home, with ~/.local/bin on PATH"
case_ good.md       0 '^ok '                 "a good guide passes"
case_ badcode.md    1 'nosuchfunction'       "a snippet that does not compile fails"
case_ badoutput.md  1 'output differs'       "wrong output fails"
case_ unlabelled.md 1 'needs a label'        "a block with no label fails"
case_ examples/ok/README.md  0 '^ok '            "an example runs in its own directory, with ../.. as the repository"
case_ examples/bad/README.md 1 'output differs'  "an example's wrong output fails"
case_ notrun.md     1 'no command ran'       "blocks no command uses fail"
exit $bad
