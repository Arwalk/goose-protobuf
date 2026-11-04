#!/usr/bin/env bash
# Build conformance_test_runner from the pinned protobuf submodule.
# Usage: scripts/build_runner.sh [build-dir]   (default: build/pb)
# Prints the runner path on stdout; build logs go to stderr.
# abseil-cpp and jsoncpp are fetched by CMake (FetchContent): needs network
# on first build. Uses the pinned protoc from .tools/ (scripts/install_toolchain.sh)
# when present, otherwise builds protoc from source too. Linux and macOS only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${1:-$root/build/pb}"
src="$root/third_party/protobuf"
pinned_protoc="$root/.tools/bin/protoc"
protoc_version="36.2"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$src/CMakeLists.txt" ] ||
  die "$src missing; run: git submodule update --init --checkout"
command -v cmake >/dev/null ||
  die "cmake not found (need >= 3.16); see TOOLCHAIN.md"
command -v c++ >/dev/null || command -v g++ >/dev/null || command -v clang++ >/dev/null ||
  die "no C++17 compiler found (gcc or clang); see TOOLCHAIN.md"

if command -v nproc >/dev/null; then jobs="$(nproc)"
else jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"; fi

{
  if [ ! -f "$build_dir/CMakeCache.txt" ]; then
    args=(
      -S "$src" -B "$build_dir"
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_CXX_STANDARD=17
      -DABSL_PROPAGATE_CXX_STD=ON
      -Dprotobuf_BUILD_CONFORMANCE=ON
      -Dprotobuf_BUILD_TESTS=OFF
      -Dprotobuf_BUILD_EXAMPLES=OFF
      -Dprotobuf_WITH_ZLIB=OFF
    )
    command -v ninja >/dev/null && args+=(-G Ninja)
    if [ -x "$pinned_protoc" ] &&
       [ "$("$pinned_protoc" --version)" = "libprotoc $protoc_version" ]; then
      echo "using pinned protoc: $pinned_protoc"
      args+=(-DWITH_PROTOC="$pinned_protoc" -Dprotobuf_BUILD_LIBUPB=OFF)
    else
      echo "no pinned protoc $protoc_version in .tools/; building protoc from source"
    fi
    cmake "${args[@]}"
  fi
  cmake --build "$build_dir" --target conformance_test_runner --parallel "$jobs"
} >&2

runner="$build_dir/conformance_test_runner"
[ -x "$runner" ] || die "build finished but $runner is missing"
echo "$runner"
