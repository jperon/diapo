# Packaging Flatpak + AppImage et CI de release — design

Date : 2026-06-27
App-ID retenu : `io.github.jperon.diapo`

## Objectif

Faciliter l'installation de **diapo** (LuaJIT/MoonScript + raylib backend SDL +
libfacedetection, déjà packagé en flake Nix) en fournissant :

1. un **AppImage** x86_64 portable, produit à partir du build Nix existant ;
2. un **Flatpak** orienté Flathub (build-from-source, runtime `org.freedesktop`),
   avec un bundle `.flatpak` installable directement ;
3. une **CI GitHub** qui, sur chaque tag `v*`, crée une release et y attache
   l'AppImage et le bundle Flatpak.

Le code de l'application n'est pas modifié. Seuls sont ajoutés des métadonnées,
des manifestes de packaging, et un workflow CI.

## Contraintes connues

- **Flathub** interdit l'accès réseau et les binaires pré-compilés pendant le
  build, et n'accepte pas la *closure* Nix. La chaîne Flatpak est donc
  indépendante de Nix et compile depuis les sources.
- raylib doit être bâti en **backend SDL** (le tactile Wayland `wl_touch` et le
  vsync économe en dépendent — cf. `AGENTS.md`).
- MoonScript doit être transpilé en `.lua`. Pour éviter d'embarquer luarocks dans
  le sandbox Flatpak, la transpilation est faite en amont par la CI (build Nix),
  qui produit un **tarball source incluant les `.lua`** consommé par le manifeste.

## 1. Métadonnées partagées (AppStream / reverse-DNS)

Renommage vers le préfixe reverse-DNS, partagé par toutes les cibles :

- `assets/diapo.svg` → `assets/io.github.jperon.diapo.svg`
- entrée `.desktop` générée sous le nom `io.github.jperon.diapo.desktop`
- nouveau `assets/io.github.jperon.diapo.metainfo.xml` (AppStream) :
  résumé, description, licence `MIT`, `developer`/`project_license`,
  `url type="homepage"` = dépôt GitHub, balise `<releases>`, et un emplacement
  `<screenshots>` balisé `TODO` (captures à fournir avant soumission Flathub —
  non bloquant pour un build local).

`flake.nix` est mis à jour pour installer l'icône et le `.desktop` sous ces
nouveaux noms, et pour installer le `metainfo.xml` dans
`$out/share/metainfo/`. Le champ `StartupWMClass` du `.desktop` reste `diapo`
(posé par le shim `diapo_appid.so` hors Flatpak).

## 2. AppImage (réutilisation du build Nix)

- Ajout d'un bundler AppImage au `flake.nix` via `nix bundle` (bundler
  `ralismark/nix-appimage` ou équivalent ajouté en input du flake).
- Sortie : `diapo-<version>-x86_64.AppImage` regroupant la closure (luajit,
  raylib SDL, les `.so`, assets). Volumineux mais autonome, cohérent avec
  l'existant.
- Vérification locale : l'AppImage se lance sur `testdata/` (`--window`).

## 3. Flatpak (orienté Flathub)

Fichier : `packaging/flatpak/io.github.jperon.diapo.yml`.

- Runtime : `org.freedesktop.Platform//25.08`, SDK correspondant (dernière
  version stable ; cadence annuelle d'août).
- Permissions (`finish-args`) :
  `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`,
  `--filesystem=host:ro` (lecture des dossiers d'images), `--share=ipc`.
- Modules build-from-source, dans l'ordre :
  1. **luajit** (tarball/git pinés, sha256) ;
  2. **raylib** : forcé en backend SDL2 (SDL2 venant du runtime ou module
     dédié si absent), options CMake `PLATFORM=SDL` / `USE_EXTERNAL_GLFW=OFF` ;
  3. **libfacedetection** : sources git pinées par commit + sha256, compilées
     avec le wrapper `csrc/facedetect_wrap.cpp` + `csrc/worker.cpp` ;
  4. **diapo** : consomme le tarball source transpilé (URL release + sha256),
     installe `src/*.lua`, `ffi/`, `assets/`, le lanceur, l'icône, le `.desktop`
     et le `metainfo.xml`.
- Le shim LD_PRELOAD `diapo_appid.so` n'est pas utilisé sous Flatpak (l'app-id
  Wayland découle de l'ID du `.desktop`). Le lanceur détecte l'absence du shim
  (déjà géré : test `[ -f … ]` dans `diapo`).
- Préparation Flathub uniquement : aucune PR vers `flathub/` n'est soumise dans
  le cadre de ce travail.

## 4. CI / Release (`.github/workflows/release.yml`)

Déclencheur : push d'un tag `v*`.

Jobs :

1. **source-tarball** : `cachix/install-nix-action` → `nix develop`/`nix build`
   pour transpiler MoonScript → `.lua`, puis crée
   `diapo-<version>-src.tar.gz` (incluant les `.lua`, `ffi/`, `csrc/`, assets,
   manifestes). Calcule son sha256.
2. **release** : crée la GitHub Release (notes auto depuis le tag) et attache le
   tarball source.
3. **appimage** : `nix bundle` → `diapo-<version>-x86_64.AppImage` → upload sur
   la release.
4. **flatpak** : `flatpak/flatpak-github-actions/flatpak-builder` (conteneur
   freedesktop), build du manifeste, export d'un bundle single-file
   `diapo-<version>.flatpak` → upload sur la release.

Note : le manifeste Flatpak référence le tarball source produit au job 1. Pour le
premier tag, l'URL/sha256 du tarball est injectée dynamiquement dans le manifeste
au moment du build CI (le manifeste versionné garde un placeholder résolu par la
CI), de sorte que `flatpak-builder` reste hors-ligne après résolution.

## Hors périmètre

- Soumission effective à Flathub (PR sur le dépôt `flathub/`).
- Captures d'écran AppStream (emplacement balisé, à fournir).
- Builds multi-architectures (aarch64) — x86_64 uniquement dans un premier temps.
- Signature des artefacts / mises à jour delta AppImage.

## Vérification

- `nix build` et `nix bundle` réussissent localement ; l'AppImage démarre sur
  `testdata/`.
- `flatpak-builder` construit le manifeste sans accès réseau (après résolution
  du tarball) et l'app se lance via `flatpak run io.github.jperon.diapo`.
- `appstreamcli validate` et `desktop-file-validate` passent sur les
  métadonnées.
- Un tag de test (`v0.0.0-test`) déclenche le workflow et produit les trois
  artefacts attachés à une release.
