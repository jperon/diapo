#!/usr/bin/env bash
# Construit l'AppImage de diapo à partir du build Nix (closure autonome).
# Usage : packaging/appimage/build.sh [arch]   (arch par défaut = uname -m)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

command -v nix >/dev/null 2>&1 || { echo "nix requis (https://nixos.org/download)" >&2; exit 1; }

ARCH="${1:-$(uname -m)}"
VERSION="$(nix eval --raw .#diapo.version)"
OUT="diapo-${VERSION}-${ARCH}.AppImage"

# nix-appimage empaquette la dérivation (et sa closure) dans un AppImage unique.
# Le bundler est câblé dans le flake (bundlers.appimage) pour garantir la reproductibilité via flake.lock.
nix bundle --bundler ".#appimage" .#diapo -o result-appimage
cp -L result-appimage "$OUT"
chmod +x "$OUT"
rm -f result-appimage
echo ">> $OUT"
