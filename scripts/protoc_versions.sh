#!/usr/bin/env bash
# Runs the golden, well-known type and round-trip tests with each protoc release of
# the supported range (decision 0014), so generated code stays the same whichever
# one a user has. Each one uses its own include directory, as it would for a user.
# Usage: scripts/protoc_versions.sh [version...]   (default: all of `versions` below)
# The releases go in .tools/other-protoc/. Linux x64 only: the plugin sees the same
# request on every platform, and the other platforms run the pin.
# Env: PLUGIN (default: scripts/build_plugin.sh), and what the three tests read, such
#      as GOLDEN_DIR (for scripts/test_protoc_versions.sh)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$root/.tools/bin" ] && export PATH="$root/.tools/bin:$PATH"

# The first releases that take editions 2024 and 2026, whose tests are left out
# before them.
first_2024=32
first_2026=36

versions="27.0 27.5 28.3 29.6 30.2 31.1 32.1 33.6 34.2 35.1 36.2"

# The pinned version comes from scripts/install_toolchain.sh, with its own sum.
sha_of() {
  case "$1" in
    27.0) echo e2bdce49564dbad4676023d174d9cdcf932238bc0b56a8349a5cb27bbafc26b0 ;;
    27.5) echo 33abede6330dd22fb9af47c2d9804ead3d86c82e025b9eef361a9ac2e955ecce ;;
    28.3) echo 0ad949f04a6a174da83cdcbdb36dee0a4925272a5b6d83f79a6bf9852076d53f ;;
    29.6) echo 48785a926e73ffa3f68e2f22b14e7b849620c7a1d36809ac9249a5495e280323 ;;
    30.2) echo 327e9397c6fb3ea2a542513a3221334c6f76f7aa524a7d2561142b67b312a01f ;;
    31.1) echo 96553041f1a91ea0efee963cb16f462f5985b4d65365f3907414c360044d8065 ;;
    32.1) echo e9c129c176bb7df02546c4cd6185126ca53c89e7d2f09511e209319704b5dd7e ;;
    33.6) echo 9c49962391ff8b5754342509efc3885db91dfe11a358e1e98c9a71518f0ad199 ;;
    34.2) echo b52e803fad2f63232f75351c0ff735e891f40262de791bade78a3636831a522a ;;
    35.1) echo 6930ebf62bd4ea607b98fff052596c6ee564b9835b4ce172c75a3f53ae9d91b7 ;;
  esac
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# unpack <version>: prints the directory of that release, fetching it if needed.
unpack() {
  local v="$1" dir want
  if [ -x "$root/.tools/protoc-$v/bin/protoc" ]; then echo "$root/.tools/protoc-$v"; return; fi
  dir="$root/.tools/other-protoc/$v"
  if [ -x "$dir/bin/protoc" ]; then echo "$dir"; return; fi
  want="$(sha_of "$v")"
  [ -n "$want" ] || { echo "no checksum recorded for protoc $v" >&2; return 1; }
  curl -fsSL --retry 3 -o "$tmp/protoc.zip" \
    "https://github.com/protocolbuffers/protobuf/releases/download/v$v/protoc-$v-linux-x86_64.zip" \
    || { echo "cannot download protoc $v" >&2; return 1; }
  if [ "$(sha256sum "$tmp/protoc.zip" | cut -d' ' -f1)" != "$want" ]; then
    echo "sha256 mismatch for protoc $v" >&2; return 1
  fi
  mkdir -p "$dir" && unzip -qo "$tmp/protoc.zip" -d "$dir" || return 1
  echo "$dir"
}

if [ -z "${PLUGIN:-}" ]; then
  "$root/scripts/build_plugin.sh" || { echo "error: scripts/build_plugin.sh failed" >&2; exit 1; }
  export PLUGIN="$root/build/protoc-gen-goose"
fi

# without_editions <pattern>: points the tests at copies of their inputs with no file
# that matches.
all_protos="${PROTO_DIR:-$root/tests/protos}"
all_roundtrips="${ROUNDTRIP_DIR:-$root/tests/roundtrip}"
restore_dirs() { export PROTO_DIR="$all_protos" ROUNDTRIP_DIR="$all_roundtrips"; }
without_editions() {
  rm -rf "$tmp/protos" "$tmp/roundtrips"
  mkdir "$tmp/protos" "$tmp/roundtrips"
  for f in "$all_protos"/*; do
    case "$(basename "$f")" in $1) ;; *) ln -s "$f" "$tmp/protos/" ;; esac
  done
  for f in "$all_roundtrips"/*; do
    case "$(basename "$f")" in $1) ;; *) ln -s "$f" "$tmp/roundtrips/" ;; esac
  done
  export PROTO_DIR="$tmp/protos" ROUNDTRIP_DIR="$tmp/roundtrips"
}

failed=()
for v in ${*:-$versions}; do
  if ! dir="$(unpack "$v")"; then failed+=("$v"); continue; fi
  export PROTOC="$dir/bin/protoc" PROTOC_INCLUDE="$dir/include"
  major="${v%%.*}"
  if [ "$major" -lt "$first_2024" ]; then without_editions 'editions_202[46]*'
  elif [ "$major" -lt "$first_2026" ]; then without_editions 'editions_2026*'
  else restore_dirs; fi
  bad=""
  for t in golden wkt roundtrip; do
    if ! "$root/scripts/$t.sh" >"$tmp/log" 2>&1; then
      bad="$bad $t"
      grep -v 'warning: Import' "$tmp/log" | sed "s/^/    /"
    fi
  done
  if [ -z "$bad" ]; then echo "PASS protoc $v"
  else echo "FAIL protoc $v:$bad"; failed+=("$v"); fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "protoc versions: failed: ${failed[*]}"; exit 1
fi
echo "protoc versions: all ok"
