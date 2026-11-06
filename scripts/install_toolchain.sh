#!/usr/bin/env bash
# Install the pinned protoc, Goose and Python protobuf (see TOOLCHAIN.md) into a
# prefix.
# Usage: scripts/install_toolchain.sh [prefix]   (default: .tools)
# Afterwards: <prefix>/bin/goose, <prefix>/bin/protoc, and <prefix>/python, a
# directory for PYTHONPATH (the pure-Python wheel, so one sha256 for all).
# Platforms: linux-x64, macos-arm64, macos-x64, and windows-x64 under Git Bash.
# Idempotent: a component
# whose pinned version is already unpacked is skipped. Every download is
# checked against the sha256 recorded below; a mismatch aborts.
set -euo pipefail

GOOSE_VERSION="v2026.3"
PROTOC_VERSION="36.2"
PY_PROTOBUF_VERSION="7.36.2"
PY_PROTOBUF_URL="https://files.pythonhosted.org/packages/e4/04/d52c7016b04b6c5108f26691f9d33ec82a9b65d041f1a9c771137693d618/protobuf-$PY_PROTOBUF_VERSION-py3-none-any.whl"
PY_PROTOBUF_SHA="bdb3a345d48db958e6ce1f18e508beb0cc981d64f24088427549c866cd039f1e"

root="$(cd "$(dirname "$0")/.." && pwd)"
prefix="${1:-$root/.tools}"
mkdir -p "$prefix"
prefix="$(cd "$prefix" && pwd)"

exe=""
goose_archive="tar.gz"
case "$(uname -s)-$(uname -m)" in
  MINGW64*-x86_64|MSYS*-x86_64)
    goose_plat="windows-x64"; protoc_plat="win64"
    goose_sha="e30cfa398c0362cef4b8f311cf5496743920b6d3a6c4a6d818fc47ee1e56be7d"
    protoc_sha="f0c128dc0d8492eceece83bb459a4c0e316764b929ffbf1aa416357fd644edd3"
    exe=".exe"; goose_archive="zip" ;;
  Linux-x86_64)
    goose_plat="linux-x64"; protoc_plat="linux-x86_64"
    goose_sha="06ac30284338269d3996d457412bf4f2b47c1f9a5601de65b6317187fe78d5c9"
    protoc_sha="121f6c7afe1d4d0e3ea6aab9432038599250134cbf4474cb1167d2c7decd4278" ;;
  Darwin-arm64)
    goose_plat="macos-arm64"; protoc_plat="osx-aarch_64"
    goose_sha="2ffaaf46b3edde27aed03fcd9ebe73e9b6639cac30d8a6915f7dc00795b7aedf"
    protoc_sha="9cd98a532c5c5e0c4161314de0225de27e4c8a323917b6ea7b1b714d3ae23466" ;;
  Darwin-x86_64)
    goose_plat="macos-x64"; protoc_plat="osx-x86_64"
    goose_sha="3c7f2895f3dcab5f39ee52808446b00688b975620d1d27e23694dd22b82abfe7"
    protoc_sha="228cc7add4616cc14ca5e80dee83209d44449a7aee95a914ae748fa374efb078" ;;
  *)
    echo "error: unsupported platform $(uname -s)-$(uname -m)" >&2
    exit 1 ;;
esac

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# fetch <url> <expected-sha256> <dest-file>
fetch() {
  local url="$1" want="$2" dest="$3" got
  curl -fsSL --retry 3 -o "$dest.part" "$url"
  got="$(sha256_of "$dest.part")"
  if [ "$got" != "$want" ]; then
    rm -f "$dest.part"
    echo "error: sha256 mismatch for $url" >&2
    echo "  expected $want" >&2
    echo "  got      $got" >&2
    exit 1
  fi
  mv "$dest.part" "$dest"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$prefix/bin"

# Goose: the release directory holds the binary next to its stdlib, so
# bin/goose is a symlink into it (goose finds its stdlib through the link).
# Git Bash's ln would copy the file instead, so there each link is a small script.
link_tool() {
  if [ -n "$exe" ]; then
    printf '#!/bin/sh\nexec "$(dirname "$0")/%s" "$@"\n' "$1$exe" >"$2"
    chmod +x "$2"
  else
    ln -sfn "$1" "$2"
  fi
}

goose_dir="$prefix/goose-$GOOSE_VERSION"
if [ ! -x "$goose_dir/goose$exe" ]; then
  name="goose-$GOOSE_VERSION-$goose_plat"
  echo "installing Goose $GOOSE_VERSION ($goose_plat)"
  fetch "https://github.com/aardappel/goose/releases/download/$GOOSE_VERSION/$name.$goose_archive" \
    "$goose_sha" "$tmp/goose.$goose_archive"
  if [ "$goose_archive" = zip ]; then
    unzip -q "$tmp/goose.zip" -d "$tmp"
  else
    tar -xzf "$tmp/goose.tar.gz" -C "$tmp"
  fi
  rm -rf "$goose_dir"
  mv "$tmp/$name" "$goose_dir"
  if [ "$(uname -s)" = Darwin ]; then
    xattr -dr com.apple.quarantine "$goose_dir" 2>/dev/null || true
  fi
else
  echo "Goose $GOOSE_VERSION already installed"
fi
link_tool "../goose-$GOOSE_VERSION/goose" "$prefix/bin/goose"

# protoc: bin/protoc plus include/ (the well-known types).
protoc_dir="$prefix/protoc-$PROTOC_VERSION"
if [ ! -x "$protoc_dir/bin/protoc$exe" ]; then
  echo "installing protoc $PROTOC_VERSION ($protoc_plat)"
  fetch "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-$protoc_plat.zip" \
    "$protoc_sha" "$tmp/protoc.zip"
  rm -rf "$protoc_dir"
  mkdir -p "$tmp/protoc"
  unzip -q "$tmp/protoc.zip" -d "$tmp/protoc"
  mv "$tmp/protoc" "$protoc_dir"
else
  echo "protoc $PROTOC_VERSION already installed"
fi
link_tool "../protoc-$PROTOC_VERSION/bin/protoc" "$prefix/bin/protoc"

# Python protobuf: a wheel is a zip, unpacked as is, with no pip or venv.
py_dir="$prefix/python"
if [ ! -d "$py_dir/protobuf-$PY_PROTOBUF_VERSION.dist-info" ]; then
  echo "installing Python protobuf $PY_PROTOBUF_VERSION"
  fetch "$PY_PROTOBUF_URL" "$PY_PROTOBUF_SHA" "$tmp/protobuf.whl"
  rm -rf "$py_dir"
  mkdir -p "$tmp/python"
  unzip -q "$tmp/protobuf.whl" -d "$tmp/python"
  mv "$tmp/python" "$py_dir"
else
  echo "Python protobuf $PY_PROTOBUF_VERSION already installed"
fi

"$prefix/bin/goose" version
"$prefix/bin/protoc" --version
echo "add to PATH: $prefix/bin"
