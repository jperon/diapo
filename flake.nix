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
    nix-appimage = {
      url = "github:ralismark/nix-appimage";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, libfacedetection, nix-appimage }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # raylib sur backend SDL (et non GLFW) : SDL implémente le protocole Wayland wl_touch,
        # ce qui fait remonter le tactile dans l'API raylib (GetTouchPointCount/GetTouchX).
        # GLFW, lui, n'expose aucun évènement tactile sous Wayland natif.
        raylib = pkgs.raylib.override { platform = "SDL"; };

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
            raylib
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
              --set RAYLIB_SO "${raylib}/lib/libraylib.so" \
              --set LUA_PATH "$share/src/?.lua;$share/ffi/?.lua;;" \
              --prefix LD_LIBRARY_PATH : "$share/lib:${raylib}/lib" \
              --prefix LD_PRELOAD : "$share/lib/diapo_appid.so" \
              --set DIAPO_APP_ID diapo \
              --set SDL_TOUCH_MOUSE_EVENTS 0

            # Entrée de menu + icône + AppStream, nommées en reverse-DNS
            # (io.github.jperon.diapo) pour la conformité Flatpak/Flathub.
            install -Dm644 assets/io.github.jperon.diapo.svg \
              "$out/share/icons/hicolor/scalable/apps/io.github.jperon.diapo.svg"
            install -Dm644 assets/io.github.jperon.diapo.metainfo.xml \
              "$out/share/metainfo/io.github.jperon.diapo.metainfo.xml"
            mkdir -p "$out/share/applications"
            cat > "$out/share/applications/io.github.jperon.diapo.desktop" <<EOF
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
            export RAYLIB_SO="${raylib}/lib/libraylib.so"
            export DIAPO_ROOT="$PWD"
            export LD_LIBRARY_PATH="$PWD/lib:${raylib}/lib:$LD_LIBRARY_PATH"
            echo "diapo: environnement prêt (raylib ${raylib.version}, $(luajit -v 2>&1 | head -1))"
          '';
        };
      });
}
