# AGENTS.md

Guide pour les agents (et humains) travaillant sur **diapo**, un diaporama Linux façon
*Fotoo* : effet Ken Burns guidé par la détection de visage.

## Vue d'ensemble

- **Langage** : MoonScript → Lua, exécuté par **LuaJIT**. Les bibliothèques C sont
  interfacées par le **FFI** de LuaJIT (jamais de binding compilé côté Lua).
- **Détection de visage** : [libfacedetection](https://github.com/ShiqiYu/libfacedetection)
  (YuNet, C++ pur, modèle embarqué) compilée en `lib/libfacedetection.so` via un wrapper
  `extern "C"`.
- **Affichage** : [raylib](https://www.raylib.com/) (GPU) ; l'effet Ken Burns est produit par
  `DrawTexturePro` en animant le rectangle source.
- **Préchargement asynchrone** : un thread worker (`csrc/worker.cpp`) avec son propre
  `lua_State` décode/détecte/planifie l'image suivante ; le thread principal ne fait que
  l'upload GPU. Synchronisation par barrière mémoire (`__sync_synchronize`).

## Structure

| Chemin | Rôle |
|--------|------|
| `src/*.moon` | sources MoonScript (seules à éditer ; les `.lua` sont générés) |
| `ffi/*.lua` | déclarations `ffi.cdef` (raylib, struct `DiapoJob`) — écrites à la main |
| `csrc/*.cpp`, `*.h` | wrapper libfacedetection, worker async, shim app_id |
| `assets/diapo.svg` | icône |
| `build.sh` | compile les `.so` + `moonc src/*.moon` |
| `flake.nix` | `nix run`/`nix build` ; build reproductible + `.desktop` + icône |
| `diapo` | lanceur (mode développement, hors Nix) |

Modules MoonScript : `main` (args/config), `config`, `scanner`, `exif`, `facedetect`,
`kenburns` (cadrage début/fin guidé visages), `display` (fenêtre/rendu/fondu), `async`
(pilotage worker), `worker` (boucle du `lua_State` secondaire), `slideshow` (orchestration).

## Build & exécution

```sh
# Développement (équivaut à nix-shell) :
nix develop
./build.sh                 # compile les .so + transpile MoonScript
./diapo testdata --window  # lance

# Via le flake (autonome) :
nix build            # -> ./result/bin/diapo
nix run . -- testdata
```

`build.sh` clone libfacedetection dans `vendor/` au premier appel. Le flake, lui, récupère
les sources via l'input `libfacedetection` (build pur, sans réseau).

## Conventions & pièges

- **N'édite que les `.moon`**, jamais les `.lua` générés (ils sont dans `.gitignore` ;
  `build.sh`/`flake.nix` lancent `moonc`). Après une modif, recompile avec
  `moonc src/<fichier>.moon` (ou `./build.sh`) avant de tester.
- **MoonScript** : pas de `*=` ni de `;` séparant des instructions (erreurs de parse) ;
  une variable locale ne peut pas être référencée par une fonction définie plus haut.
- **`ffi/jobdef.lua` et `csrc/diapo_job.h` doivent rester strictement identiques** (même
  struct `DiapoJob` des deux côtés) : toute divergence corrompt l'échange entre threads.
- **FFI** : `libfacedetection.so` est chargée via `$DIAPO_ROOT/lib/…` ; `raylib` via
  `$RAYLIB_SO`. Ces variables sont posées par le lanceur `diapo` et par le wrapper du flake.
- **Threads** : aucun `lua_State` ne traverse les threads ; le worker a le sien. Toute
  donnée partagée passe par `DiapoJob` + barrière mémoire — ne pas contourner.
- **BGR vs RGB** : libfacedetection attend du BGR ; raylib charge en RGB → conversion dans
  `facedetect.moon`. Toujours travailler sur une copie (`ImageCopy`) pour ne pas corrompre
  l'image affichée.
- **Mémoire GPU** : libérer (`UnloadTexture`/`UnloadImage`) les ressources de l'image
  sortante ; un diaporama tourne longtemps.

## Tests

Pas de suite formelle. Vérifications usuelles :

- `./build.sh` se termine sans erreur (compilation `.so` + `moonc`).
- `./result/bin/diapo --help` et un lancement sur `testdata/` (3 images : un visage NASA
  domaine public, un footballeur, une scène).
- `--debug-faces` dessine les rectangles détectés (contrôle visuel du cadrage).
- Le worker peut être validé en logique pure (LuaJIT) quand la GUI n'est pas observable :
  l'environnement headless suspend les *frame callbacks* Wayland après ~1 s.

## Git

- Branche par défaut : `master`. Remote : `github:jperon/diapo` (consommé par `nix run`).
- `testdata/`, `vendor/`, `lib/`, `build/`, les `src/*.lua` et `config.lua` sont ignorés.
- **Ne jamais committer d'images sous copyright** dans `testdata/` (préférer le domaine
  public ; Lenna a été retirée délibérément).
- Messages de commit en français, concis.
