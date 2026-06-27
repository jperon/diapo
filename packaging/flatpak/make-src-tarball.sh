#!/usr/bin/env bash
# Produit packaging/flatpak/diapo-src.tar.gz contenant les sources nécessaires
# au build Flatpak : .lua transpilés (jamais édités à la main), ffi, csrc,
# assets reverse-DNS, config d'exemple et lanceur. Transpilation via moonc (Nix).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Transpile MoonScript -> Lua dans un shell Nix (moonc disponible).
nix develop --command moonc src/*.moon

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/diapo"
cp -r src ffi csrc assets config.example.lua "$STAGE/diapo/"
cp packaging/flatpak/diapo-launcher.sh "$STAGE/diapo/"
# On n'embarque pas les .moon ni les .so (recompilés dans le sandbox).
find "$STAGE/diapo/src" -name '*.moon' -delete
rm -rf "$STAGE/diapo/lib"

# .desktop reverse-DNS (même contenu que le flake) pour l'installer dans Flatpak.
cat > "$STAGE/diapo/assets/io.github.jperon.diapo.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=diapo
GenericName=Diaporama Ken Burns
Comment=Diaporama automatique Ken Burns guidé par la détection de visage
Exec=diapo %F
Icon=io.github.jperon.diapo
Terminal=false
Categories=Graphics;Viewer;
StartupWMClass=diapo
EOF

tar -C "$STAGE" -czf packaging/flatpak/diapo-src.tar.gz diapo
rm -rf "$STAGE"
echo ">> packaging/flatpak/diapo-src.tar.gz"
