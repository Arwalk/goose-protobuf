#!/usr/bin/env bash
# Self-test for scripts/selfhost_tests.sh: it passes on generator-goose/, and
# changing any value of any feature default in features.goose makes it fail.
# Usage: scripts/test_selfhost_tests.sh
# Env: as scripts/selfhost_tests.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0

out="$("$root/scripts/selfhost_tests.sh" 2>&1)" || { echo "FAIL the unchanged generator"; echo "$out"; bad=1; }

check_change() {  # check_change <constant> <from> <to>
  local changed
  rm -rf "$tmp/src"; mkdir "$tmp/src"
  cp -R "$root"/generator-goose/. "$tmp/src/"
  changed="$(python3 -c '
import sys
constant, old, new, path = sys.argv[1:]
lines = open(path).read().split("\n")
hits = [i for i, l in enumerate(lines) if l.startswith("let " + constant + " = Features {")]
if len(hits) != 1 or old not in lines[hits[0]]: sys.exit(constant + " or " + old + " not found")
lines[hits[0]] = lines[hits[0]].replace(old, new)
open(path, "w").write("\n".join(lines))
' "$1" "$2" "$3" "$tmp/src/features.goose" 2>&1)" || {
    echo "FAIL $1 $2: $changed"; bad=1; return; }
  if out="$(GENERATOR_SRC="$tmp/src" "$root/scripts/selfhost_tests.sh" 2>&1)"; then
    echo "FAIL $1 with $3 passed"; bad=1
  elif grep -q "differs from protoc" <<<"$out"; then
    echo "PASS $1 with $3 fails"
  else
    echo "FAIL $1 with $3 failed some other way"; echo "$out"; bad=1
  fi
}

for constant in proto2_defaults proto3_defaults edition_2023_defaults; do
  for field in closed_enum packed_repeated verify_utf8 delimited; do
    case "$(grep "^let $constant = Features {" "$root/generator-goose/features.goose")" in
      *"$field: true"*) check_change "$constant" "$field: true" "$field: false" ;;
      *) check_change "$constant" "$field: false" "$field: true" ;;
    esac
  done
  case "$(grep "^let $constant = Features {" "$root/generator-goose/features.goose")" in
    *"presence: PRESENCE_IMPLICIT"*) check_change "$constant" "presence: PRESENCE_IMPLICIT" "presence: PRESENCE_EXPLICIT" ;;
    *) check_change "$constant" "presence: PRESENCE_EXPLICIT" "presence: PRESENCE_IMPLICIT" ;;
  esac
done
exit $bad
