{
  description = "diapo — diaporama Ken Burns guidé par la détection de visage (LuaJIT/MoonScript + raylib)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # libfacedetection : sources C++ (YuNet) compilées dans la dérivation.
    libfacedetection = {
      url = "github:ShiqiYu/libfacedetection";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, libfacedetection }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        diapo = pkgs.stdenv.mkDerivation {
          pname = "diapo";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [
            pkgs.gcc
            pkgs.luajit
            pkgs.luajitPackages.moonscript
            pkgs.makeWrapper
          ];

          buildInputs = [
            pkgs.luajit
            pkgs.raylib
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p lib

            # En-têtes LuaJIT : on récupère le bon répertoire (le nom de version varie).
            LJ_INC="$(dirname "$(find ${pkgs.luajit}/include -name lua.h | head -1)")"

            echo ">> compilation libfacedetection.so"
            g++ -O3 -fPIC -shared -std=c++11 \
                -I"${libfacedetection}/src" -I"$PWD/csrc" -I"$LJ_INC" \
                -fvisibility=hidden \
                ${libfacedetection}/src/*.cpp \
                csrc/facedetect_wrap.cpp \
                csrc/worker.cpp \
                -L"${pkgs.luajit}/lib" -lluajit-5.1 -lpthread \
                -o lib/libfacedetection.so

            echo ">> compilation diapo_appid.so"
            g++ -O2 -fPIC -shared -std=c++11 csrc/diapo_appid.cpp -ldl \
                -o lib/diapo_appid.so

            echo ">> moonc src/*.moon"
            moonc src/*.moon

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            share="$out/share/diapo"
            mkdir -p "$share/lib" "$out/bin"

            cp -r src ffi assets "$share/"
            cp lib/libfacedetection.so lib/diapo_appid.so "$share/lib/"
            cp config.example.lua "$share/" || true

            # Le code charge $DIAPO_ROOT/lib/libfacedetection.so (cf. facedetect.moon),
            # d'où DIAPO_ROOT = $share et les .so dans $share/lib.
            makeWrapper ${pkgs.luajit}/bin/luajit "$out/bin/diapo" \
              --add-flags "$share/src/main.lua" \
              --set DIAPO_ROOT "$share" \
              --set RAYLIB_SO "${pkgs.raylib}/lib/libraylib.so" \
              --set LUA_PATH "$share/src/?.lua;$share/ffi/?.lua;;" \
              --prefix LD_LIBRARY_PATH : "$share/lib:${pkgs.raylib}/lib" \
              --prefix LD_PRELOAD : "$share/lib/diapo_appid.so" \
              --set DIAPO_APP_ID diapo

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Diaporama automatique Ken Burns guidé par la détection de visage";
            homepage = "https://github.com/jperon/diapo";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "diapo";
          };
        };
      in {
        packages.default = diapo;
        packages.diapo = diapo;
        apps.default = {
          type = "app";
          program = "${diapo}/bin/diapo";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            luajit
            luajitPackages.moonscript
            raylib
            gcc
            git
          ];
          shellHook = ''
            export RAYLIB_SO="${pkgs.raylib}/lib/libraylib.so"
            export DIAPO_ROOT="$PWD"
            export LD_LIBRARY_PATH="$PWD/lib:${pkgs.raylib}/lib:$LD_LIBRARY_PATH"
            echo "diapo: environnement prêt (raylib ${pkgs.raylib.version}, $(luajit -v 2>&1 | head -1))"
          '';
        };
      });
}
