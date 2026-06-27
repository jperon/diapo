# diapo

Diaporama automatique pour Linux combinant l'effet **Ken Burns** (zoom + panoramique lent)
avec la **détection de visage**, à la manière de l'application Android *Fotoo* : le mouvement
de caméra est cadré pour que les visages restent visibles et bien centrés.

- **Langage** : MoonScript → Lua, exécuté par **LuaJIT**.
- **Détection de visage** : [libfacedetection](https://github.com/ShiqiYu/libfacedetection)
  (YuNet, C++ pur sans dépendance), interfacée par **FFI**.
- **Affichage** : [raylib](https://www.raylib.com/) (GPU), via **FFI** ; l'effet Ken Burns
  est produit par `DrawTexturePro` en animant le rectangle source. raylib est compilé sur le
  backend **SDL** (et non GLFW) : sous Wayland natif, seul SDL transmet le tactile (`wl_touch`)
  et offre un vsync qui met la boucle en veille (≈ 4 % CPU au lieu de saturer un cœur).
- **Formats d'image** : JPEG, PNG, BMP, GIF, TGA décodés directement par raylib. Les formats
  récents (WebP, AVIF, HEIC/HEIF, JPEG 2000, TIFF) sont pris en charge via un **repli de
  conversion** : si raylib ne sait pas décoder un fichier, il est converti à la volée en PNG
  par **ImageMagick** (`magick`/`convert`). Une image illisible (format non géré sans
  ImageMagick, fichier corrompu) est simplement **ignorée** sans bloquer le diaporama.

## Installation

### AppImage (Linux, sans Nix)

Téléchargez le fichier `diapo-<version>-<arch>.AppImage` depuis les
[releases GitHub](https://github.com/jperon/diapo/releases), puis :

```sh
chmod +x diapo-*.AppImage
./diapo-*.AppImage <dossier>          # diaporama plein écran
./diapo-*.AppImage                    # ouvre un sélecteur de dossier
```

L'AppImage est autonome : il embarque LuaJIT, raylib (SDL), libfacedetection et
tous les assets — aucune dépendance système requise.

Pour construire localement depuis les sources :

```sh
packaging/appimage/build.sh           # produit diapo-<version>-<arch>.AppImage
```

### Installation / lancement avec Nix (flake)

Le plus simple, sans rien cloner ni compiler à la main :

```sh
nix run github:jperon/diapo -- ~/Photos     # ou sans dossier : sélecteur graphique
nix run github:jperon/diapo                 # ouvre un sélecteur de dossier
```

Depuis une copie locale :

```sh
nix run /chemin/vers/diapo -- ~/Photos
nix build /chemin/vers/diapo                # produit ./result/bin/diapo
```

Le flake compile lui-même `libfacedetection.so` et le shim `diapo_appid.so`, transpile le
MoonScript en Lua, et installe un binaire `diapo` autonome (chemins des `.so`, `RAYLIB_SO`,
`LUA_PATH` et `LD_PRELOAD` déjà câblés). Il installe aussi l'**entrée de menu** et l'**icône**
(`share/applications/diapo.desktop`, `share/icons/hicolor/scalable/apps/diapo.svg`) : `diapo`
apparaît dans le lanceur d'applications et son icône/nom dans Alt+Tab (l'app_id `diapo` du
shim correspond au `StartupWMClass`). `nix develop` fournit l'environnement de développement
(≈ `nix-shell`).

Sur NixOS, l'ajouter à la configuration suffit (input du flake + paquet dans
`environment.systemPackages`) pour avoir la commande **et** l'entrée de menu au niveau
système.

## Dépendances (développement)

Fournies par `shell.nix` / `nix develop` (NixOS) : `luajit`, `luajitPackages.moonscript`,
`raylib`, `imagemagick` (repli de décodage des formats récents), `gcc`, `git`.

```sh
nix-shell           # entre dans l'environnement
./build.sh          # compile libfacedetection.so + les sources MoonScript
./diapo ~/Photos    # lance le diaporama (plein écran)
./diapo             # sans dossier : ouvre un sélecteur de dossier graphique
```

Sans argument de dossier, `diapo` ouvre un **sélecteur de dossier** en essayant, dans
l'ordre, les boîtes de dialogue disponibles (`zenity`, `qarma`, `matedialog`, `yad`,
`kdialog`, `Xdialog`) — donc indépendamment du bureau utilisé. Si aucune n'est installée,
un message invite à en installer une ou à passer le dossier en argument.

Ou en une fois :

```sh
nix-shell --run './build.sh'
nix-shell --run './diapo ~/Photos'
```

## Options

```
./diapo <dossier> [options]
  --config <fichier>   fichier de configuration Lua (voir config.example.lua)
                       défaut : ./config.lua, sinon ~/.local/share/diapo/config.lua
  --window             mode fenêtré
  --no-shuffle         ordre déterministe (par défaut alphabétique ; voir --order)
  --order <liste>      priorité d'ordonnancement (implique --no-shuffle), critères
                       séparés par des virgules parmi : folder, exif, similarity
                       (ex. folder,similarity = parcours visuellement fluide par dossier)
  --detect-rotated     détecte aussi sur ±90° même si un visage est déjà trouvé (plus lent ;
                       utile pour les dossiers mêlant photos à l'endroit et tournées)
  --debug-faces        affiche les rectangles des visages détectés
  --keep-eyes / --no-keep-eyes  garder les yeux des sujets dans la vue (défaut : oui)
  --no-face-focus      cadre tous les visages à la fois (défaut : zoome sur un seul visage,
                       tiré au hasard à chaque passage de l'image)
  --face-delta-max <n> écart de score maximal sous le meilleur visage pour rester éligible au
                       tirage (0 = illimité ; ex. 12 : meilleur à 93 → un visage à 80 est ignoré)
  --zoom-out <f>       dézoom max au-delà de l'image (ex. 1.3) avec fond flou autour
  --zoom-max <f>       magnification max de la vue serrée (0 = pas de limite)
  --zoom-min <f>       magnification min de la vue large (plancher)
  --no-blur            fond noir au lieu du fond flou
  --speed <f>          vitesse de l'effet (1 = une traversée par durée d'affichage)
  --no-bounce          désactive l'aller-retour (rebond)
  --easing <f>         accélération/décélération (1 = linéaire, 2 = doux, >2 = marqué)
  --duration <s>       durée par image (mouvement)
  --fade <s>           durée du fondu (ajoutée à la durée)
```

### Icône et nom dans le gestionnaire de fenêtres

Sous Wayland, le nom et l'icône (Alt+Tab, dock) dépendent de l'*app_id* de la fenêtre, que
raylib ne définit pas (d'où « Inconnu » sans icône). Le lanceur précharge un petit shim
(`lib/diapo_appid.so`) qui pose l'app_id `diapo`. L'installation via le flake (ou
`environment.systemPackages` sur NixOS) fournit déjà l'entrée `diapo.desktop` et l'icône de
même nom, que le gestionnaire de fenêtres associe à cet app_id (`StartupWMClass=diapo`).

### Économie d'énergie

Quand la fenêtre est **minimisée/masquée**, le rendu se met en pause (horloge gelée pour ne
pas « sauter » au retour) — voir `pause_hidden`. Avec `pause_unfocused` (ou
`--pause-unfocused`), la pause s'étend aux fenêtres sans focus. La détection d'occlusion
*totale* par une autre fenêtre n'est pas exposée par GNOME ; sous Wayland+vsync, une fenêtre
entièrement masquée voit toutefois ses *frame callbacks* suspendus, ce qui throttle déjà le
rendu.

### Mode d'affichage

Le plein écran n'est **pas** une contrainte : raylib gère le mode fenêtré tout aussi bien.
Par défaut le diaporama est en plein écran ; `--window` (ou `fullscreen = false`) démarre en
**fenêtre redimensionnable** dont la taille initiale est réglable (`window_width` /
`window_height`). La touche **`F`** bascule plein écran ↔ fenêtré à la volée (retour à la
taille de fenêtre mémorisée). Le cadrage s'adapte en continu à la taille de la fenêtre.

### Navigation

- **Clavier** : `→` / `Espace` image suivante · `←` / `Retour arrière` image précédente ·
  `F` bascule plein écran ↔ fenêtré · `Échap` / `Q` quitter. Les touches *caractère*
  (`F`, `Q`) suivent la **disposition active** (bépo, azerty…) : elles réagissent au
  caractère réellement saisi, pas à la position physique de la touche.
- **Souris** : clic dans la **moitié droite** de l'écran = suivante, **moitié gauche** =
  précédente.
- **Tactile** : un toucher agit comme un clic (moitié droite = suivante, gauche =
  précédente). Nécessite le backend SDL de raylib (cf. ci-dessous), seul à transmettre
  le tactile sous Wayland.

La navigation interrompt l'image en cours **avec un fondu** (jamais une coupure sèche).
L'image sortante ne s'arrête pas net : elle poursuit son mouvement **en décélérant**
pendant le fondu (glissé), depuis sa vitesse au moment de l'interruption jusqu'à l'arrêt.

Le cadrage s'adapte à l'**orientation de l'écran** (paysage ou portrait) : la taille réelle
de la surface est lue après l'application du plein écran, et suivie à chaque frame (une
rotation de l'écran en cours d'exécution est prise en compte). La résolution détectée est
affichée au démarrage.

## Options notables

- **`keep_eyes`** : étend les vues de début et de fin pour qu'elles contiennent les yeux
  (landmarks YuNet) de tous les visages ; comme l'interpolation est linéaire, les yeux
  restent visibles pendant tout le mouvement.
- **`zoom_out`** (>1) : autorise une vue plus large que l'image (effet « recul »). Le dézoom
  est plafonné pour qu'une seule dimension (largeur **ou** hauteur) dépasse l'image —
  l'autre reste pleine, donc le fond n'apparaît que sur deux côtés. La zone hors image est
  comblée par **`background`** : `"blur"` (copie réduite et floutée, façon arrière-plan
  dépoli) ou `"black"`.
- **`speed`**, **`bounce`**, **`easing`** : `speed` règle la vitesse du mouvement
  indépendamment de la durée d'affichage ; si le mouvement se termine avant la fin de
  l'affichage, `bounce` fait un aller-retour (ping-pong) ; `easing` contrôle
  l'accélération/décélération (1 = linéaire, 2 = doux, plus = plus marqué). Lorsque
  `speed > 1`, le mouvement (qui rebondit) **décélère** sur une fenêtre finale pour
  s'immobiliser juste avant le fondu, évitant tout arrêt brusque.
- **`face_arc`** : pendant le mouvement le cadrage dévie légèrement (bosse sinusoïdale, nulle
  aux extrémités) puis revient à son cadrage final. La déviation est **bi-axe** : son vecteur
  est proportionnel à l'écart du sujet au centre de l'image (sujet décentré → bosse diagonale ;
  sujet centré → bosse quasi nulle). `face_arc` règle l'amplitude.
- **`face_arc_dir`** : sens de la bosse — `"toward"` (vers le sujet), `"away"` (à l'opposé) ou
  `"both"` (tiré au hasard à chaque image, défaut). Le sens tiré reste stable pendant la diapo
  (y compris lors d'un redimensionnement de fenêtre).
- **`zoom_max` / `zoom_min`** : bornes explicites de magnification (relative à la vue
  plein-cadre). Le zoom serré effectif vaut `min(zoom_max, zoom_calculé)` (évite de trop
  zoomer sur un petit visage) ; le zoom large effectif vaut `max(zoom_min, zoom_calculé)`.
  `0` = pas de limite.
- **`harmonize`** : fait **coïncider les visages** de deux images consécutives pendant le
  fondu. La vue de fin de l'image sortante et la vue de départ de l'entrante sont calculées
  **conjointement** : on cherche un placement écran commun du visage (position + taille), pour
  que les deux visages se superposent au moment du fondu. Priorité à la coïncidence, puis au
  bon positionnement de chaque image (éviter une vue trop désaxée), enfin à l'harmonisation du
  zoom — une imprécision « poétique » est tolérée. Les marges `harmonize_zoom_tol` (écart
  relatif de taille) et `harmonize_pos_tol` (décalage de position, fraction d'écran) bornent
  cette tolérance ; au-delà, on retombe sur les vues naturelles. Une image sans visage détecté
  garde le cadrage centré habituel. `harmonize = false` rétablit le comportement indépendant.
- **Fondu sur image immobile** : le fondu enchaîné a lieu **après** le mouvement Ken Burns,
  sur des images figées (l'ancienne sur sa dernière vue, la nouvelle sur sa première), et sa
  durée s'**ajoute** à celle de l'animation (temps total par image = `duration + fade`).
- **Préchargement asynchrone** : un thread worker dédié (avec son propre `lua_State`)
  effectue le décodage, l'EXIF, la détection et le calcul du plan ; le thread principal ne
  fait que l'upload GPU. Le rendu reste fluide pendant la préparation de l'image suivante.
  Repli automatique en mode synchrone si le worker ne démarre pas. La synchronisation
  entre threads emploie une barrière mémoire (`__sync_synchronize`) autour du drapeau
  d'état, donc l'ordre des écritures/lectures est garanti même sur architectures à modèle
  mémoire faible (ARM, Raspberry Pi…).

## Override manuel des visages (`.diapo`)

Dans de rares cas, la détection automatique échoue (visage de profil, peu contrasté,
partiellement masqué). On peut alors **déclarer les visages à la main** dans un fichier caché
`.diapo` (un fichier Lua) placé dans le dossier d'images. Il renvoie une table associant un
chemin (relatif au `.diapo`, sous-dossiers autorisés) à une liste de visages, en **coordonnées
normalisées** `[0..1]` (fraction de la largeur/hauteur, après rotation EXIF) :

```lua
-- .diapo
return {
  ["portrait.jpg"]    = { { x = 0.42, y = 0.30, w = 0.12, h = 0.18 } },
  ["sous/groupe.jpg"] = { { x = 0.20, y = 0.25, w = 0.10, h = 0.15 },
                          { x = 0.55, y = 0.28, w = 0.10, h = 0.15 } },
}
```

Quand une image est listée, ses visages déclarés **remplacent** la détection automatique (qui
est alors sautée). Si plusieurs `.diapo` couvrent la même image (un à la racine, un dans un
sous-dossier), le **plus profond l'emporte**. Les visages manuels n'ont pas de landmarks
(yeux) : `keep_eyes` est sans effet sur eux. Une clé peut aussi être un **chemin absolu**.

Au démarrage, le chargement est journalisé : chaque `.diapo` lu (nombre d'images ciblées), le
nombre d'images effectivement couvertes, et — surtout — un avertissement pour toute clé
**sans image correspondante** (faute de casse, mauvais chemin relatif…). Si l'override semble
ignoré, vérifier ces messages : la clé doit correspondre exactement au chemin de l'image tel
que listé (relatif au `.diapo`).

## Architecture

| Fichier              | Rôle                                                            |
|----------------------|-----------------------------------------------------------------|
| `csrc/facedetect_wrap.cpp` | wrapper `extern "C"` de libfacedetection                  |
| `csrc/worker.cpp`    | worker de préchargement : thread + second `lua_State`           |
| `csrc/diapo_job.h`   | struct d'échange thread principal ↔ worker                      |
| `ffi/raylib.lua`     | déclarations FFI raylib                                          |
| `ffi/jobdef.lua`     | cdef partagé de `DiapoJob` (miroir de `diapo_job.h`)            |
| `src/facedetect.moon`| FFI libfacedetection, conversion RGB→BGR, parsing des visages   |
| `src/kenburns.moon`  | rectangles début/fin guidés par les visages, `keep_eyes`, `zoom_out` |
| `src/display.moon`   | fenêtre, textures, rendu (vue→écran), fond flou, fondu          |
| `src/scanner.moon`   | parcours récursif du dossier                                    |
| `src/exif.moon`      | orientation EXIF                                                |
| `src/async.moon`     | pilotage du worker côté thread principal (submit/poll/upload)   |
| `src/worker.moon`    | boucle du worker (exécutée dans le `lua_State` secondaire)      |
| `src/slideshow.moon` | orchestration : préchargement async, fondu, alternance du zoom  |
| `src/main.moon`      | point d'entrée, arguments, configuration                        |
