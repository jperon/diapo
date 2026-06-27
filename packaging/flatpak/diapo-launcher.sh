#!/bin/bash
# Lanceur de diapo dans le sandbox Flatpak.
set -euo pipefail
export DIAPO_ROOT="/app/share/diapo"
export RAYLIB_SO="/app/lib/libraylib.so"
export LUA_PATH="$DIAPO_ROOT/src/?.lua;$DIAPO_ROOT/ffi/?.lua;;"
export LD_LIBRARY_PATH="$DIAPO_ROOT/lib:/app/lib:${LD_LIBRARY_PATH:-}"
# Backend SDL : couper l'émulation tactile->souris (cf. AGENTS.md / lanceur dev).
export SDL_TOUCH_MOUSE_EVENTS=0
exec luajit "$DIAPO_ROOT/src/main.lua" "$@"
