#!/usr/bin/env bash
# Lance les tests (à exécuter dans nix-shell pour disposer de moonc, luajit, raylib).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
moonc src/*.moon tests/*.moon
export RAYLIB_SO="${RAYLIB_SO:-raylib}"
export DIAPO_ROOT="$ROOT"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
rc=0
for spec in tests/*_spec.lua; do
  LUA_PATH="src/?.lua;ffi/?.lua;tests/?.lua;;" luajit "$spec" || rc=1
done
exit $rc
