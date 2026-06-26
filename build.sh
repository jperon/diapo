#!/usr/bin/env bash
# Build des dépendances natives + compilation MoonScript -> Lua.
# À lancer dans `nix-shell` (voir shell.nix) pour disposer de g++, git, moonc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VENDOR="$ROOT/vendor/libfacedetection"
LIBDIR="$ROOT/lib"
mkdir -p "$LIBDIR" "$ROOT/vendor"

# 1. Récupération de libfacedetection (sources uniquement, pas de build CMake).
if [ ! -d "$VENDOR" ]; then
  echo ">> clone libfacedetection"
  git clone --depth 1 https://github.com/ShiqiYu/libfacedetection.git "$VENDOR"
fi

# 2. Compilation de libfacedetection + wrapper en .so.
#    On compile directement les sources de src/ (aucune dépendance externe).
echo ">> compilation libfacedetection.so"
EXTRA_FLAGS=""
# SIMD : AVX2 sur x86_64, sinon rien (NEON activé par défaut sur ARM par la lib).
if grep -q avx2 /proc/cpuinfo 2>/dev/null; then
  EXTRA_FLAGS="-mavx2 -mfma -D_ENABLE_AVX2"
fi
# Chemins LuaJIT (headers + lib) dérivés du binaire luajit, pour le worker async.
LJ_PREFIX="$(cd "$(dirname "$(readlink -f "$(command -v luajit)")")/.." && pwd)"
LJ_INC="$(dirname "$(find "$LJ_PREFIX/include" -name lua.h | head -1)")"

g++ -O3 -fPIC -shared -std=c++11 $EXTRA_FLAGS \
    -I"$VENDOR/src" -I"$ROOT/csrc" -I"$LJ_INC" \
    -fvisibility=hidden \
    "$VENDOR"/src/*.cpp \
    "$ROOT/csrc/facedetect_wrap.cpp" \
    "$ROOT/csrc/worker.cpp" \
    -L"$LJ_PREFIX/lib" -lluajit-5.1 -lpthread \
    -o "$LIBDIR/libfacedetection.so"
echo "   -> $LIBDIR/libfacedetection.so"

# 2b. Shim LD_PRELOAD pour l'app_id Wayland / la classe X11 (icône + nom dans Alt+Tab).
echo ">> compilation diapo_appid.so (shim app_id)"
g++ -O2 -fPIC -shared -std=c++11 "$ROOT/csrc/diapo_appid.cpp" -ldl \
    -o "$LIBDIR/diapo_appid.so"
echo "   -> $LIBDIR/diapo_appid.so"

# 3. Compilation MoonScript -> Lua dans build/.
if ls src/*.moon >/dev/null 2>&1; then
  echo ">> moonc src/*.moon -> src/*.lua"
  moonc src/*.moon
else
  echo ">> (aucune source MoonScript pour l'instant)"
fi

echo ">> terminé."
