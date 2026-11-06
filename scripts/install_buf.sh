#!/usr/bin/env bash
# Install the pinned buf (see TOOLCHAIN.md) into a prefix, for scripts/check_docs.py,
# which runs docs/build-systems.md, and scripts/buf_golden.sh. Nothing else here needs
# it, so it is apart from scripts/install_toolchain.sh, which users run.
# Usage: scripts/install_buf.sh [prefix]   (default: .tools)
# Afterwards: <prefix>/bin/buf. Idempotent. The download is checked against the sha256
# recorded below; a mismatch aborts.
set -euo pipefail

BUF_VERSION="1.75.0"

root="$(cd "$(dirname "$0")/.." && pwd)"
prefix="${1:-$root/.tools}"
mkdir -p "$prefix/bin"
prefix="$(cd "$prefix" && pwd)"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    file="buf-Linux-x86_64"; want="fad1e38d6909bbb583a4da81d8c02a01046e2cd663bde7e337dd24277393764b" ;;
  Darwin-arm64)
    file="buf-Darwin-arm64"; want="f71b009ebd8530b12fd85b060c6c245e15d6e5110ccc8da48d8b6fa71e59330b" ;;
  Darwin-x86_64)
    file="buf-Darwin-x86_64"; want="ff6d0979143c661d59178a032c57be883b2ac03dc9bf7d00ffca222b0354bd46" ;;
  *)
    echo "error: unsupported platform $(uname -s)-$(uname -m)" >&2
    exit 1 ;;
esac

dest="$prefix/bin/buf"
if [ -x "$dest" ] && [ "$("$dest" --version)" = "$BUF_VERSION" ]; then
  echo "buf $BUF_VERSION already installed"
  exit 0
fi

curl -fsSL --retry 3 -o "$dest.part" \
  "https://github.com/bufbuild/buf/releases/download/v$BUF_VERSION/$file"
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$dest.part" | cut -d' ' -f1)"
else
  got="$(shasum -a 256 "$dest.part" | cut -d' ' -f1)"
fi
if [ "$got" != "$want" ]; then
  rm -f "$dest.part"
  echo "error: sha256 mismatch for $file: expected $want, got $got" >&2
  exit 1
fi
chmod +x "$dest.part"
mv "$dest.part" "$dest"
"$dest" --version
