#!/usr/bin/env bash
# Build conformance_test_runner from the pinned protobuf submodule.
# Usage: scripts/build_runner.sh [build-dir]   (default: build/pb)
# abseil-cpp and jsoncpp are fetched by CMake (FetchContent): needs network
# on first build. Linux and macOS only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${1:-$root/build/pb}"
src="$root/third_party/protobuf"

if [ ! -f "$src/CMakeLists.txt" ]; then
  echo "error: $src missing; run: git submodule update --init" >&2
  exit 1
fi

cmake -S "$src" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -Dprotobuf_BUILD_CONFORMANCE=ON \
  -Dprotobuf_BUILD_TESTS=OFF
cmake --build "$build_dir" --target conformance_test_runner --parallel

echo "$build_dir/conformance_test_runner"
