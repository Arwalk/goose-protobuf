#!/usr/bin/env bash
# Install the pinned protoc and Goose (see TOOLCHAIN.md) into a prefix.
# Usage: scripts/install_toolchain.sh [prefix]   (default: .tools)
# Afterwards: <prefix>/bin/goose and <prefix>/bin/protoc.
# Platforms: linux-x64, macos-arm64, macos-x64. Idempotent: a component
# whose pinned version is already unpacked is skipped. Every download is
# checked against the sha256 recorded below; a mismatch aborts.
set -euo pipefail

GOOSE_VERSION="v2026.3"
PROTOC_VERSION="36.2"

root="$(cd "$(dirname "$0")/.." && pwd)"
prefix="${1:-$root/.tools}"
mkdir -p "$prefix"
prefix="$(cd "$prefix" && pwd)"

case "$(uname -s)-$(uname -m)" in
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
goose_dir="$prefix/goose-$GOOSE_VERSION"
if [ ! -x "$goose_dir/goose" ]; then
  name="goose-$GOOSE_VERSION-$goose_plat"
  echo "installing Goose $GOOSE_VERSION ($goose_plat)"
  fetch "https://github.com/aardappel/goose/releases/download/$GOOSE_VERSION/$name.tar.gz" \
    "$goose_sha" "$tmp/goose.tar.gz"
  tar -xzf "$tmp/goose.tar.gz" -C "$tmp"
  rm -rf "$goose_dir"
  mv "$tmp/$name" "$goose_dir"
  if [ "$(uname -s)" = Darwin ]; then
    xattr -dr com.apple.quarantine "$goose_dir" 2>/dev/null || true
  fi
else
  echo "Goose $GOOSE_VERSION already installed"
fi
ln -sfn "../goose-$GOOSE_VERSION/goose" "$prefix/bin/goose"

# protoc: bin/protoc plus include/ (the well-known types).
protoc_dir="$prefix/protoc-$PROTOC_VERSION"
if [ ! -x "$protoc_dir/bin/protoc" ]; then
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
ln -sfn "../protoc-$PROTOC_VERSION/bin/protoc" "$prefix/bin/protoc"

"$prefix/bin/goose" version
"$prefix/bin/protoc" --version
echo "add to PATH: $prefix/bin"
