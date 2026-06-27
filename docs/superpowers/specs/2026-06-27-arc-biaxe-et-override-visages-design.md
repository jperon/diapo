# Arc Ken Burns bi-axe & override manuel des visages — design

Date : 2026-06-27

Deux améliorations indépendantes du diaporama `diapo` :

1. l'arc Ken Burns (`face_arc`) doit dévier le cadrage sur **les deux axes** selon la
   position du sujet dans l'image, et non plus seulement verticalement ;
2. permettre de **déclarer manuellement** les visages d'une image via un fichier `.diapo`,
   pour les cas où la détection automatique échoue.

Le code est en MoonScript (`src/*.moon` → `src/*.lua` générés). Toute modification se fait
dans les `.moon`, puis recompilation. La structure FFI partagée worker ↔ thread principal est
définie en double : `ffi/jobdef.lua` (Lua) et `csrc/diapo_job.h` (C) — les deux doivent rester
synchronisées.

---

## Partie 1 — Arc Ken Burns bi-axe

### État actuel

`kenburns.at (kb, e, arc=0)` applique une bosse purement verticale :

```moon
r.y += arc * r.h * math.sin math.pi * e
```

La bosse est nulle aux extrémités (`sin 0 = sin π = 0`) et maximale au milieu du mouvement.
L'amplitude `arc` vaut `cfg.face_arc` (défaut 0.12). L'écrêtage par axe respecte `free_x`/`free_y`
(axes « libres » où du fond est visible : pas d'écrêtage, pour éviter le zig-zag).

### Cible

La bosse suit un **vecteur dérivé de la position du sujet**, avec composantes proportionnelles
à l'écart au centre, et un **sens tiré au hasard** (vers le sujet / depuis le sujet) parmi les
sens activés en configuration. L'ancien comportement vertical pur **disparaît** (un sujet centré
horizontalement produit naturellement une bosse quasi verticale).

### Calcul du vecteur (dans `kenburns.plan`)

À partir du centre du sous-ensemble cadré (`bbox` du `sel`, déjà calculé) et du centre image :

```
dx = clamp((cx_sujet − img_w/2) / (img_w/2), −1, 1)
dy = clamp((cy_sujet − img_h/2) / (img_h/2), −1, 1)
```

- `cx_sujet, cy_sujet` = centre de `bbox` (sous-ensemble cadré : visage `focus` seul, ou tous).
- Sans visage (`bbox == nil`) : `dx = dy = 0` → arc neutre (aucune bosse).
- Proportionnel à l'écart : sujet centré → bosse faible ; sujet en coin → bosse diagonale marquée.

### Tirage du sens

Un sens `sign ∈ {+1, −1}` :

- `+1` = **vers le sujet** : le cadrage bombe dans la direction où se trouve le sujet (le vecteur
  `(dx, dy)` pointe déjà vers le sujet).
- `−1` = **depuis le sujet** : bombe à l'opposé.

Le pool tirable dépend de la config `face_arc_dir` :

| `face_arc_dir` | pool       |
|----------------|------------|
| `"toward"`     | `{+1}`     |
| `"away"`       | `{−1}`     |
| `"both"` (déf.)| `{+1, −1}` |

Tirage à la construction de la diapo. Le sens est **mémorisé** (comme `focus`) et repassé tel quel
lors d'un recalcul du plan (resize, `slideshow:148`) afin que l'arc reste stable pendant la diapo.

`kenburns.plan` :
- accepte `opts.arc_dir` (chaîne) et `opts.arc_sign` (optionnel ; si fourni, force le sens au lieu
  de tirer — utilisé au recalcul) ;
- stocke dans le plan retourné : `arc_dx = sign·dx`, `arc_dy = sign·dy`, et `arc_sign` (sens choisi,
  pour mémorisation).

### Application (dans `kenburns.at`)

```moon
if arc != 0
  r.x += arc * (kb.arc_dx or 0) * r.w * math.sin math.pi * e
  r.y += arc * (kb.arc_dy or 0) * r.h * math.sin math.pi * e
```

L'écrêtage par axe existant (`unless kb.free_x` / `unless kb.free_y`) est conservé inchangé.
`kb.arc_dx`/`kb.arc_dy` absents (plan reconstruit côté `async`) → `0` (pas de bosse), donc le
plan FFI doit transporter ces champs (voir ci-dessous).

### Acheminement worker (FFI)

Le plan est calculé dans le worker (`worker.moon`) ; `async.finalize` reconstruit un plan léger à
partir des champs bruts du job. Ajouts à `DiapoJob` (`ffi/jobdef.lua` **et** `csrc/diapo_job.h`) :

```c
double arc_dx, arc_dy;   /* composantes de la bosse, signe inclus */
int    arc_sign;         /* sens tiré (+1/−1), mémorisé pour recalcul */
```

- `async.submit` code `cfg.face_arc_dir` en `int arc_dir_mode` (0=toward, 1=away, 2=both) et le
  passe au job. Le worker tire lui-même le sens à partir de ce mode, puis publie
  `arc_dx/arc_dy/arc_sign`. (Le sens n'est jamais forcé via le job : la mémorisation pour le
  recalcul se fait côté thread principal, qui rappelle `kenburns.plan` localement avec
  `opts.arc_sign`.)
- `async.finalize` recopie `arc_dx`, `arc_dy` dans le plan reconstruit, et `arc_sign` dans la diapo.
- Au recalcul (`slideshow:148`), `prepare`/le plan local reçoit `opts.arc_sign = s.arc_sign` et
  `opts.arc_dir` pour reproduire exactement la même bosse.

Le chemin synchrone (`slideshow.prepare`) calcule le plan directement et mémorise `plan.arc_sign`
dans la diapo (`s.arc_sign`).

### Config

- `face_arc` (existant) : amplitude scalaire, inchangé.
- `face_arc_dir` (nouveau) : `"toward" | "away" | "both"`, défaut `"both"`.

Documenter dans `config.example.lua`, `src/config.moon` (valeur par défaut) et le `--help`/README si
pertinent.

---

## Partie 2 — Override manuel des visages (`.diapo`)

### Format du fichier

Fichier caché `.diapo`, **Lua**, un par dossier. Renvoie une table `nom_relatif → liste de visages`.
Coordonnées **normalisées dans [0, 1]** (fraction de la largeur/hauteur de l'image, après rotation
EXIF). Les clés peuvent désigner des fichiers de sous-dossiers (chemin relatif au `.diapo`).

```lua
-- .diapo
return {
  ["photo.jpg"]       = { { x = 0.42, y = 0.30, w = 0.12, h = 0.18 } },
  ["sous/groupe.jpg"] = { { x = 0.20, y = 0.25, w = 0.10, h = 0.15 },
                          { x = 0.55, y = 0.28, w = 0.10, h = 0.15 } },
}
```

Un visage = `{ x, y, w, h }` (coin supérieur-gauche + taille, normalisés). `score` optionnel
(défaut élevé, p. ex. 100, pour que `weighted_index` le traite comme fiable).

### Résolution (dans `scanner`)

`scanner.scan` collecte aussi les fichiers nommés `.diapo` rencontrés par `find` (ils ne passent
pas le filtre `EXT`, donc à capter explicitement). Pour chacun :

1. `loadfile` en bac à sable (environnement vide : pas d'accès global), exécution protégée ;
   en cas d'erreur, on émet un avertissement sur `stderr` et on ignore ce fichier.
2. Pour chaque clé, on résout le chemin absolu relatif au dossier du `.diapo` ; on valide les
   coordonnées (nombres dans [0,1], `w>0`, `h>0`), on ignore et signale les entrées invalides.
3. On construit `overrides[abspath] = { faces normalisés, depth = profondeur du .diapo }`.

**Règle « le plus profond gagne »** : si plusieurs `.diapo` couvrent la même image, l'entrée dont
le `.diapo` a la plus grande profondeur (chemin le plus long / le plus de séparateurs) l'emporte.

`scanner.scan` retourne désormais `paths, meta, overrides`. `order.order` ignore `overrides`.
`main` transmet `overrides` à `slideshow.run`.

### Sémantique

Présence d'une entrée pour une image → **remplace** la détection automatique : le worker (ou
`prepare`) saute `detect_image` et utilise exclusivement les visages déclarés (économie CPU).
`focus`, plan Ken Burns et arc se calculent ensuite normalement à partir de ces visages.

### Acheminement worker (FFI)

Les visages d'override sont normalisés ; ils sont convertis en pixels une fois l'image chargée
(dimensions connues, post-EXIF). On réutilise le buffer `faces[320]` (= 64×5) du job comme
**entrée** :

- nouveau champ `int override_nfaces;` dans `DiapoJob` (`jobdef.lua` + `diapo_job.h`) ;
- `async.submit (path, cfg, reverse, aspect, override)` : si `override`, écrit jusqu'à 64 visages
  normalisés dans `j.faces` (`x,y,w,h,score` par visage) et `j.override_nfaces = n` ; sinon `0` ;
- `worker.process` : si `override_nfaces > 0`, lit les visages, convertit
  `x*iw, y*ih, w*iw, h*ih`, **saute** `detect_image` ; sinon comportement actuel. La suite
  (focus, plan, écriture des faces de debug dans `job.faces`) est inchangée — le buffer est relu en
  premier puis réécrit en sortie.

Le chemin synchrone (`slideshow.prepare (path, cfg, reverse, override)`) : si `override`, convertit
en pixels après chargement/EXIF et saute `detect_image`.

`slideshow.run` reçoit `overrides` et, à chaque `submit`/`prepare`, passe `overrides[path]`.

### Limites

- Pas de landmarks (yeux) sur les visages manuels → `keep_eyes` est sans effet sur eux
  (`eye_points` les ignore déjà). Acceptable : cas de secours.
- Max 64 visages par image (capacité du buffer existant).

---

## Tests

`tests/` utilise des `*_spec.moon` (voir `kenburns_spec.moon`, `run.sh`).

- **kenburns** : `at` avec `arc_dx/arc_dy` — sujet décentré → bosse diagonale (x et y déviés) ;
  sujet centré (`dx=dy=0`) → aucune bosse ; sens `+1` vs `−1` opposés. `plan` : `arc_sign` forcé
  reproduit le même `arc_dx/arc_dy` ; calcul de `dx,dy` clampé dans [−1,1].
- **scanner / override** : parsing d'un `.diapo` valide ; résolution de chemins de sous-dossiers ;
  règle « le plus profond gagne » ; rejet d'entrées invalides (hors [0,1], w/h ≤ 0) ; conversion
  normalisé → pixels correcte pour des dimensions données.
- **régression** : `face_arc_dir = "toward"` avec un seul visage donne une bosse stable et
  déterministe ; `face_arc = 0` → aucune déviation.

## Fichiers touchés

- `src/kenburns.moon` — `plan` (calcul `dx,dy`, tirage/mémorisation du sens) et `at` (bi-axe).
- `src/config.moon`, `config.example.lua` — `face_arc_dir`.
- `src/scanner.moon` — collecte + parsing `.diapo`, map `overrides`.
- `src/main.moon` — transmet `overrides` à `slideshow.run`.
- `src/slideshow.moon` — `prepare`/`run` reçoivent et propagent `override` et l'arc mémorisé.
- `src/async.moon`, `src/worker.moon` — champs FFI, override en entrée, arc en sortie.
- `ffi/jobdef.lua`, `csrc/diapo_job.h` — nouveaux champs (`arc_dx`, `arc_dy`, `arc_sign`,
  `arc_dir_mode`, `override_nfaces`).
- `tests/kenburns_spec.moon`, nouveau `tests/scanner_spec.moon` (ou équivalent).
- `README.md` / `--help` — documentation des nouveautés.
