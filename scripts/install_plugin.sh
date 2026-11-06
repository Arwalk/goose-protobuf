#!/usr/bin/env bash
# Builds the plugin and copies it to <prefix>/bin, so that protoc, which looks for
# protoc-gen-goose on PATH, needs no --plugin. The copy stands alone: it needs
# neither this checkout nor Goose to run. Says so on stderr if the directory is not
# on PATH. Prints the installed path on stdout.
# Usage: scripts/install_plugin.sh [prefix]   (default ~/.local)
# Env: as scripts/build_plugin.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
prefix="${1:-$HOME/.local}"
"$root/scripts/build_plugin.sh"

mkdir -p "$prefix/bin"
bin="$(cd "$prefix/bin" && pwd)"
# Through a temporary name, so a protoc running the old one is not disturbed.
cp "$root/build/protoc-gen-goose" "$bin/.protoc-gen-goose.$$"
chmod 755 "$bin/.protoc-gen-goose.$$"
mv -f "$bin/.protoc-gen-goose.$$" "$bin/protoc-gen-goose"
echo "$bin/protoc-gen-goose"

case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "$bin is not on PATH. Add it: export PATH=\"$bin:\$PATH\"" >&2 ;;
esac
