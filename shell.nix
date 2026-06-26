{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  # Outils de build + dépendances d'exécution.
  buildInputs = with pkgs; [
    luajit
    luajitPackages.moonscript   # fournit `moonc`
    raylib                      # libraylib.so
    gcc                         # g++ pour compiler libfacedetection
    git
  ];

  # Expose les chemins des .so au FFI via des variables d'environnement
  # (ffi.load les lit dans display.moon / facedetect.moon).
  shellHook = ''
    export RAYLIB_SO="${pkgs.raylib}/lib/libraylib.so"
    export DIAPO_ROOT="$PWD"
    export LD_LIBRARY_PATH="$PWD/lib:${pkgs.raylib}/lib:$LD_LIBRARY_PATH"
    echo "diapo: environnement prêt (raylib ${pkgs.raylib.version}, $(luajit -v 2>&1 | head -1))"
  '';
}
