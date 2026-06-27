#!/usr/bin/env bash
# Construit l'AppImage de diapo à partir du build Nix (closure autonome).
# Usage : packaging/appimage/build.sh [arch]   (arch par défaut = uname -m)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARCH="${1:-$(uname -m)}"
VERSION="$(nix eval --raw .#diapo.version)"
OUT="diapo-${VERSION}-${ARCH}.AppImage"

# nix-appimage empaquette la dérivation (et sa closure) dans un AppImage unique.
nix bundle --bundler github:ralismark/nix-appimage .#diapo -o result-appimage
cp -L result-appimage "$OUT"
chmod +x "$OUT"
echo ">> $OUT"
