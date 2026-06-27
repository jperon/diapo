# Packaging Flatpak + AppImage + CI de release — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fournir une installation simple de diapo via un AppImage (issu du build Nix) et un Flatpak orienté Flathub, plus une CI GitHub qui crée une release et y attache ces artefacts à chaque tag `v*`.

**Architecture:** Aucune modification du code applicatif. On ajoute (1) des métadonnées partagées au format reverse-DNS `io.github.jperon.diapo` (icône, `.desktop`, AppStream `metainfo.xml`), (2) un bundler AppImage branché sur le `flake.nix` existant, (3) un manifeste `flatpak-builder` compilant depuis les sources avec un tarball de `.lua` transpilés produit en amont, (4) un workflow CI multi-arch (x86_64 + aarch64).

**Tech Stack:** Nix flakes, `nix bundle` + bundler `nix-appimage`, `flatpak-builder` (runtime `org.freedesktop.Platform//25.08`), GitHub Actions, AppStream.

## Global Constraints

- **App-ID / reverse-DNS** : `io.github.jperon.diapo` (icône, `.desktop`, metainfo, manifeste).
- **raylib backend SDL** obligatoire (tactile Wayland `wl_touch` + vsync économe ; cf. `AGENTS.md`). Jamais GLFW.
- **Runtime Flatpak** : `org.freedesktop.Platform//25.08` (+ SDK `25.08`).
- **Architectures cibles** : `x86_64` et `aarch64` pour toutes les sorties.
- **Flathub** : build-from-source, hors-ligne, aucun binaire pré-compilé. La transpilation MoonScript→Lua est faite en amont (tarball source).
- **Permissions Flatpak** : `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`, `--share=ipc`, `--filesystem=host:ro`.
- **Ne jamais éditer les `.lua` à la main** (générés par `moonc`). Les manifestes consomment des `.lua` transpilés, ils ne les écrivent pas.
- Messages de commit en français, concis.
- Déclencheur CI : push d'un tag `v*`.

---

### Task 1: Métadonnées partagées (reverse-DNS + AppStream)

Renomme l'icône et l'entrée de menu vers le préfixe reverse-DNS et ajoute le fichier AppStream, puis adapte `flake.nix` pour installer ces noms. C'est le socle commun aux trois cibles.

**Files:**
- Rename: `assets/diapo.svg` → `assets/io.github.jperon.diapo.svg`
- Create: `assets/io.github.jperon.diapo.metainfo.xml`
- Modify: `flake.nix` (installPhase : icône, `.desktop`, metainfo)
- Modify: `AGENTS.md:30` (ligne du tableau `assets/diapo.svg`)

**Interfaces:**
- Produces : fichiers `io.github.jperon.diapo.{svg,desktop,metainfo.xml}` installés sous `$out/share/...`, réutilisés tels quels par les Tasks 3 et 4.

- [ ] **Step 1: Renommer l'icône (en préservant l'historique git)**

```bash
git mv assets/diapo.svg assets/io.github.jperon.diapo.svg
```

- [ ] **Step 2: Créer le fichier AppStream**

Créer `assets/io.github.jperon.diapo.metainfo.xml` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.jperon.diapo</id>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <name>diapo</name>
  <summary>Diaporama Ken Burns guidé par la détection de visage</summary>
  <developer id="io.github.jperon">
    <name>jperon</name>
  </developer>
  <description>
    <p>
      diapo est un diaporama pour Linux façon Fotoo : il enchaîne les images
      d'un dossier avec un effet Ken Burns (zoom et panoramique lents) dont le
      cadrage est guidé par la détection de visage, pour garder les personnes
      bien dans le champ. Affichage GPU via raylib, navigation au clavier et au
      toucher.
    </p>
  </description>
  <launchable type="desktop-id">io.github.jperon.diapo.desktop</launchable>
  <url type="homepage">https://github.com/jperon/diapo</url>
  <url type="bugtracker">https://github.com/jperon/diapo/issues</url>
  <categories>
    <category>Graphics</category>
    <category>Viewer</category>
  </categories>
  <content_rating type="oars-1.1" />
  <!-- TODO Flathub : ajouter au moins une capture d'écran avant soumission.
       <screenshots>
         <screenshot type="default">
           <image>https://raw.githubusercontent.com/jperon/diapo/master/assets/screenshot.png</image>
         </screenshot>
       </screenshots> -->
  <releases>
    <release version="0.1.0" date="2026-06-27"/>
  </releases>
</component>
```

- [ ] **Step 3: Adapter l'installPhase du flake (icône + desktop + metainfo)**

Dans `flake.nix`, remplacer le bloc `install -Dm644 assets/diapo.svg ...` jusqu'au `EOF` du `.desktop` par :

```nix
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
```

- [ ] **Step 4: Mettre à jour la ligne d'assets dans AGENTS.md**

Remplacer `| `assets/diapo.svg` | icône |` par `| `assets/io.github.jperon.diapo.svg` | icône |`.

- [ ] **Step 5: Construire et valider les métadonnées**

Run :
```bash
nix build .#diapo
desktop-file-validate result/share/applications/io.github.jperon.diapo.desktop
appstreamcli validate --no-net result/share/metainfo/io.github.jperon.diapo.metainfo.xml || \
  appstream-util validate-relax result/share/metainfo/io.github.jperon.diapo.metainfo.xml
```
Expected : `nix build` réussit ; `desktop-file-validate` ne renvoie aucune erreur ; la validation AppStream passe (warnings sur les captures d'écran tolérés — `TODO` documenté).

- [ ] **Step 6: Commit**

```bash
git add assets flake.nix AGENTS.md
git commit -m "feat(packaging): métadonnées AppStream + reverse-DNS io.github.jperon.diapo"
```

---

### Task 2: AppImage via `nix bundle`

Branche un bundler AppImage sur le flake existant et expose une invocation reproductible. L'AppImage réutilise la closure Nix (luajit, raylib SDL, `.so`, assets).

**Files:**
- Modify: `flake.nix` (inputs : ajout de `nix-appimage`)
- Create: `packaging/appimage/build.sh`
- Modify: `README.md` (section installation : mention AppImage)

**Interfaces:**
- Consumes : `packages.diapo` du flake (Task 1).
- Produces : script `packaging/appimage/build.sh <arch>` qui dépose `diapo-<version>-<arch>.AppImage` dans le répertoire courant ; réutilisé par la CI (Task 4).

- [ ] **Step 1: Ajouter le bundler aux inputs du flake**

Dans `flake.nix`, dans le bloc `inputs = { ... };`, ajouter :

```nix
    nix-appimage = {
      url = "github:ralismark/nix-appimage";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

Ajouter `nix-appimage` à la liste des arguments de `outputs = { self, nixpkgs, flake-utils, libfacedetection, nix-appimage }:`.

- [ ] **Step 2: Verrouiller le nouvel input**

Run : `nix flake lock`
Expected : `flake.lock` mis à jour avec une entrée `nix-appimage`, sans erreur.

- [ ] **Step 3: Écrire le script de build AppImage**

Créer `packaging/appimage/build.sh` :

```bash
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
```

Puis : `chmod +x packaging/appimage/build.sh`.

- [ ] **Step 4: Construire et vérifier l'AppImage localement**

Run :
```bash
packaging/appimage/build.sh
./diapo-*-"$(uname -m)".AppImage testdata --window &
sleep 5 && kill %1 2>/dev/null || true
```
Expected : un fichier `diapo-<version>-<arch>.AppImage` exécutable est produit ; il démarre et affiche une fenêtre sur `testdata/` (l'environnement graphique doit être disponible ; sinon, vérifier au minimum `./diapo-*.AppImage --help`).

- [ ] **Step 5: Documenter l'AppImage dans le README**

Ajouter dans le README une sous-section « Installation » mentionnant le téléchargement de l'AppImage depuis les releases GitHub, `chmod +x diapo-*.AppImage`, puis `./diapo-*.AppImage <dossier>`.

- [ ] **Step 6: Commit**

```bash
git add flake.nix flake.lock packaging/appimage/build.sh README.md
git commit -m "feat(packaging): AppImage via nix bundle (nix-appimage)"
```

---

### Task 3: Manifeste Flatpak (build-from-source)

Crée le manifeste `flatpak-builder` et le script de tarball source. Le module `diapo` consomme une archive locale `diapo-src.tar.gz` (`.lua` déjà transpilés) produite par le script, garantissant un build hors-ligne sans luarocks dans le sandbox.

**Files:**
- Create: `packaging/flatpak/io.github.jperon.diapo.yml`
- Create: `packaging/flatpak/make-src-tarball.sh`
- Create: `packaging/flatpak/diapo-launcher.sh`
- Create: `packaging/flatpak/README.md`

**Interfaces:**
- Consumes : métadonnées de la Task 1 (icône, `.desktop`, metainfo) ; sources `src/`, `ffi/`, `csrc/`, `assets/`.
- Produces : manifeste buildable par `flatpak-builder` ; script `make-src-tarball.sh` produisant `packaging/flatpak/diapo-src.tar.gz` ; lanceur installé comme `/app/bin/diapo`. Réutilisés par la CI (Task 4).

- [ ] **Step 1: Script de génération du tarball source transpilé**

Créer `packaging/flatpak/make-src-tarball.sh` :

```bash
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

tar -C "$STAGE" -czf packaging/flatpak/diapo-src.tar.gz diapo
rm -rf "$STAGE"
echo ">> packaging/flatpak/diapo-src.tar.gz"
```

Puis : `chmod +x packaging/flatpak/make-src-tarball.sh`.

- [ ] **Step 2: Lanceur Flatpak**

Créer `packaging/flatpak/diapo-launcher.sh` (installé en `/app/bin/diapo`). Sous Flatpak, pas de shim LD_PRELOAD (l'app-id Wayland découle du `.desktop`) :

```bash
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
```

Puis : `chmod +x packaging/flatpak/diapo-launcher.sh`.

- [ ] **Step 3: Manifeste flatpak-builder**

Créer `packaging/flatpak/io.github.jperon.diapo.yml` :

```yaml
app-id: io.github.jperon.diapo
runtime: org.freedesktop.Platform
runtime-version: '25.08'
sdk: org.freedesktop.Sdk
command: diapo
finish-args:
  - --socket=wayland
  - --socket=fallback-x11
  - --share=ipc
  - --device=dri
  - --filesystem=host:ro
modules:
  - name: luajit
    no-autogen: true
    make-args:
      - BUILDMODE=dynamic
      - PREFIX=/app
    make-install-args:
      - PREFIX=/app
    sources:
      - type: archive
        url: https://luajit.org/download/LuaJIT-2.1.ROLLING.tar.gz
        # TODO : figer une release LuaJIT + sha256 réelle avant soumission Flathub.
        sha256: 0000000000000000000000000000000000000000000000000000000000000000
    cleanup:
      - /bin/luajit-*

  - name: raylib
    buildsystem: cmake-ninja
    config-opts:
      - -DCMAKE_BUILD_TYPE=Release
      - -DBUILD_SHARED_LIBS=ON
      - -DPLATFORM=SDL
      - -DUSE_EXTERNAL_GLFW=OFF
    sources:
      - type: archive
        url: https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz
        sha256: 0000000000000000000000000000000000000000000000000000000000000000

  - name: diapo
    buildsystem: simple
    build-commands:
      # Wrapper libfacedetection (YuNet) + worker async, compilés en .so.
      - >-
        g++ -O3 -fPIC -shared -std=c++11
        -I libfacedetection/src -I diapo/csrc -I /app/include/luajit-2.1
        -fvisibility=hidden
        libfacedetection/src/*.cpp
        diapo/csrc/facedetect_wrap.cpp diapo/csrc/worker.cpp
        -L /app/lib -lluajit-5.1 -lpthread
        -o libfacedetection.so
      - install -Dm644 libfacedetection.so /app/share/diapo/lib/libfacedetection.so
      - cp -r diapo/src diapo/ffi diapo/assets /app/share/diapo/
      - install -Dm644 diapo/config.example.lua /app/share/diapo/config.example.lua
      - install -Dm755 diapo/diapo-launcher.sh /app/bin/diapo
      - install -Dm644 diapo/assets/io.github.jperon.diapo.svg
        /app/share/icons/hicolor/scalable/apps/io.github.jperon.diapo.svg
      - install -Dm644 diapo/assets/io.github.jperon.diapo.metainfo.xml
        /app/share/metainfo/io.github.jperon.diapo.metainfo.xml
      - install -Dm644 diapo/assets/io.github.jperon.diapo.desktop
        /app/share/applications/io.github.jperon.diapo.desktop
    sources:
      - type: archive
        path: diapo-src.tar.gz
        strip-components: 0
      - type: git
        url: https://github.com/ShiqiYu/libfacedetection.git
        commit: e0e8e0d2c4e0b06f6a4e3a1b0e7e0c1f0000000
        # TODO : figer un commit réel de libfacedetection avant soumission.
        dest: libfacedetection
```

Note : le `.desktop` reverse-DNS n'est pas dans la closure du tarball (généré par le flake) ; on l'ajoute au tarball via `make-src-tarball.sh`. **Corriger le script** : ajouter à l'étape 1 la génération du `.desktop` et son inclusion — voir Step 4.

- [ ] **Step 4: Compléter le tarball avec `.desktop` reverse-DNS**

Le `.desktop` est généré par le flake, pas présent en source. Ajouter dans `make-src-tarball.sh`, juste avant la ligne `tar -C ...` :

```bash
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
```

- [ ] **Step 5: README de packaging Flatpak**

Créer `packaging/flatpak/README.md` documentant : (1) `./make-src-tarball.sh` pour produire `diapo-src.tar.gz` ; (2) build local :
```bash
cd packaging/flatpak
./make-src-tarball.sh
flatpak install -y flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
flatpak-builder --user --install --force-clean build io.github.jperon.diapo.yml
flatpak run io.github.jperon.diapo testdata
```
(3) note sur les `sha256`/commits `TODO` à figer avant soumission Flathub, et que le tarball `diapo-src.tar.gz` est ignoré par git.

- [ ] **Step 6: Ignorer le tarball généré**

Ajouter à `.gitignore` :
```
/packaging/flatpak/diapo-src.tar.gz
/packaging/flatpak/build/
/packaging/flatpak/.flatpak-builder/
/result-appimage
*.AppImage
*.flatpak
```

- [ ] **Step 7: Vérifier le build Flatpak localement**

Run :
```bash
cd packaging/flatpak
./make-src-tarball.sh
flatpak-builder --user --force-clean build io.github.jperon.diapo.yml
```
Expected : `flatpak-builder` compile luajit, raylib (SDL), libfacedetection et installe diapo sans erreur. (Si les `sha256`/commit `TODO` ne sont pas encore figés, l'étape échoue au téléchargement : les renseigner d'abord à partir des vraies sources — voir README.) En cas d'indisponibilité de `flatpak-builder` en local, au minimum lancer `flatpak-builder --show-manifest io.github.jperon.diapo.yml` pour valider la syntaxe.

- [ ] **Step 8: Commit**

```bash
git add packaging/flatpak .gitignore
git commit -m "feat(packaging): manifeste Flatpak build-from-source (Flathub-ready)"
```

---

### Task 4: CI GitHub — release multi-arch sur tag

Workflow déclenché sur tag `v*` : crée la release et y attache, pour `x86_64` et `aarch64`, le tarball source, l'AppImage et le bundle Flatpak.

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes : `packaging/appimage/build.sh` (Task 2), `packaging/flatpak/io.github.jperon.diapo.yml` + `make-src-tarball.sh` (Task 3).
- Produces : artefacts attachés à la GitHub Release.

- [ ] **Step 1: Écrire le workflow**

Créer `.github/workflows/release.yml` :

```yaml
name: release
on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Créer la release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true

  appimage:
    needs: release
    strategy:
      matrix:
        include:
          - arch: x86_64
            runner: ubuntu-latest
          - arch: aarch64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
      - name: Construire l'AppImage
        run: packaging/appimage/build.sh ${{ matrix.arch }}
      - name: Attacher à la release
        uses: softprops/action-gh-release@v2
        with:
          files: diapo-*-${{ matrix.arch }}.AppImage

  flatpak:
    needs: release
    strategy:
      matrix:
        include:
          - arch: x86_64
            runner: ubuntu-latest
          - arch: aarch64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
      - name: Générer le tarball source (.lua transpilés)
        run: packaging/flatpak/make-src-tarball.sh
      - name: Installer flatpak-builder
        run: |
          sudo apt-get update
          sudo apt-get install -y flatpak flatpak-builder
          flatpak remote-add --user --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo
      - name: Build + export du bundle
        working-directory: packaging/flatpak
        run: |
          VERSION="$(nix eval --raw "$GITHUB_WORKSPACE#diapo.version")"
          flatpak-builder --user --install-deps-from=flathub \
            --repo=repo --force-clean build io.github.jperon.diapo.yml
          flatpak build-bundle repo \
            "$GITHUB_WORKSPACE/diapo-${VERSION}-${{ matrix.arch }}.flatpak" \
            io.github.jperon.diapo
      - name: Attacher à la release
        uses: softprops/action-gh-release@v2
        with:
          files: diapo-*-${{ matrix.arch }}.flatpak
```

- [ ] **Step 2: Valider la syntaxe du workflow**

Run :
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```
Expected : `YAML OK`. (Si `actionlint` est disponible : `actionlint .github/workflows/release.yml` sans erreur.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release multi-arch (AppImage + Flatpak) sur tag v*"
```

- [ ] **Step 4: Vérification de bout en bout (manuelle, sur le dépôt distant)**

Après fusion sur `master`, pousser un tag de test :
```bash
git tag v0.0.0-test && git push origin v0.0.0-test
```
Expected : le workflow `release` s'exécute, crée la release `v0.0.0-test` et y attache `diapo-0.1.0-{x86_64,aarch64}.AppImage` et `diapo-0.1.0-{x86_64,aarch64}.flatpak`. Supprimer ensuite la release et le tag de test.

---

## Notes d'exécution

- **`sha256`/commits `TODO`** (LuaJIT, raylib, libfacedetection) : à renseigner avec les vraies valeurs lors de la Task 3, Step 7, en récupérant les archives réelles (`nix-prefetch-url <url>` pour le sha256, `git ls-remote` pour le commit). Le plan les laisse en placeholder explicite car ils dépendent des versions retenues au moment de l'implémentation.
- **Soumission Flathub** : hors périmètre (PR sur `flathub/`). Les `TODO` captures d'écran et sources figées sont les prérequis restants.
