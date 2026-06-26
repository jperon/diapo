#!/usr/bin/env bash
# Installe l'icône et le fichier .desktop pour que le diaporama apparaisse avec son nom
# et son icône (Alt+Tab, lanceur d'applications). L'app_id de la fenêtre est "diapo"
# (posé par le shim lib/diapo_appid.so) ; GNOME l'associe au .desktop de même identifiant.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$APPS" "$ICONS"

cp "$ROOT/assets/diapo.svg" "$ICONS/diapo.svg"

# Exec lance le diaporama dans l'environnement nix-shell du projet.
cat > "$APPS/diapo.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=diapo
GenericName=Diaporama Ken Burns
Comment=Diaporama automatique Ken Burns guidé par la détection de visage
Exec=bash -lc 'cd "$ROOT" && nix-shell --run "./diapo %F"'
Icon=diapo
Terminal=false
Categories=Graphics;Viewer;
StartupWMClass=diapo
EOF

# Rafraîchit les caches (best effort).
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
command -v gtk-update-icon-cache  >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

echo "Installé :"
echo "  $APPS/diapo.desktop"
echo "  $ICONS/diapo.svg"
echo "L'icône/nom apparaîtront dans Alt+Tab au prochain lancement via ./diapo."
