# Transitions harmonisées : coïncidence des visages au fondu — design

Date : 2026-06-28

## Problème

Pendant un fondu enchaîné, on superpose la **vue de fin** de l'image sortante et la **vue de
départ** de l'image entrante (cf. `slideshow.moon` : `draw_slide fade_from … p_out` puis
`draw_slide cur … progress(0)`). Deux défauts cosmétiques :

1. une image « dézoomée » (extrémité large) est toujours **centrée** : aux transitions
   large↔large, les visages des deux images ne coïncident pas ;
2. le zoom serré va toujours au **maximum** déduit de `zoom_max` et du visage : aux transitions
   serré↔serré, les visages ont des tailles écran différentes selon l'image.

## Objectif

À chaque transition, calculer **conjointement** la vue de fin de la sortante et la vue de
départ de l'entrante pour, par ordre de priorité :

1. faire **coïncider les deux visages** à l'écran (position + taille) pendant le fondu ;
2. ensuite, **bien positionner** chaque image (éviter qu'une vue soit trop désaxée / trop
   écrêtée contre les bords) ;
3. harmoniser le **zoom effectif** (taille des deux visages voisins), sans exiger l'égalité
   parfaite — une imprécision « poétique » est tolérée, bornée par des marges configurables.

Image sans visage détecté : **repli** sur le comportement actuel (zoom centré + dérive douce),
sans tentative d'harmonisation à ses transitions.

## Modèle géométrique

Une **vue** est un rectangle `(x,y,w,h)` en coordonnées image, au ratio écran `aspect`, mappé
plein écran. Pour un visage de centre `(fcx,fcy)` et de hauteur `fh` (coord. image), vu sous `V` :

- position écran du visage : `sx = (fcx - V.x)/V.w`, `sy = (fcy - V.y)/V.h` (∈ [0,1]) ;
- taille écran du visage : `hs = fh / V.h` (fraction de la hauteur écran).

On appelle **placement** le triplet `P = (sx, sy, hs)` : où le visage apparaît et sa taille.

**Vue à partir d'un placement** (fonction inverse, déterministe) — `view_for_placement` :

```
V.h = fh / hs        V.w = V.h * aspect
V.x = fcx - sx * V.w  V.y = fcy - sy * V.h
```

Placer les visages des deux images au **même** `P` ⇒ ils coïncident exactement à l'écran. Tout
l'enjeu est de choisir un `P` réalisable par les deux images.

### Réalisabilité d'un placement pour une image

Contraintes pour `view_for_placement(face, P)` sur une image `iw×ih` :

- **Zoom** : `zoom = full.w / V.w` doit rester dans `[zmin_eff, zmax_eff]` (bornes déjà
  calculées aujourd'hui à partir de `zoom_min`/`zoom_max`/`zoom_out` et du visage). `hs` fixe
  `V.h` donc le zoom : `hs` grand ⇒ zoom serré.
- **Bornes image** : sur un axe non « libre » (pas de fond flou), `V` doit tenir dans
  `[0,iw]×[0,ih]`. Pour un `hs` (donc `V.w`,`V.h`) donné, cela borne `sx`,`sy` :
  `sx ∈ [ (fcx + V.w - iw)/V.w , fcx/V.w ] ∩ [0,1]` (idem `sy`). Sur un axe libre
  (`zoom_out>1`), le débordement est autorisé (fond flou) → pas de borne.

D'où, par image et par `hs` : une plage de `hs` admissible `[hs_min, hs_max]` (du zoom) et,
pour un `hs` fixé, des plages admissibles `sx∈[..]`, `sy∈[..]`.

## Calcul du placement conjoint

À une transition entre A (sortante, son extrémité de rencontre) et B (entrante, son extrémité
de rencontre) — qui sont, par l'alternance zoom-in/out, **de même nature** (toutes deux serrées
ou toutes deux larges) :

1. **Nature** → cible de taille de visage de base `hs0` : grande pour une transition serrée
   (dérivée de `zoom_max`/marge), petite pour une large (dérivée de `zoom_out`/`zoom_min`).
2. **Taille (hs)** : `hs = clamp(hs0, max(hsA_min,hsB_min), min(hsA_max,hsB_max))`. Si les
   plages ne se recouvrent pas, prendre la **moyenne géométrique** des bornes les plus proches ;
   si l'écart relatif dépasse `harmonize_zoom_tol`, **renoncer** (repli vues naturelles).
3. **Position (sx,sy)** : partir de `(0.5,0.5)` ; intersecter les plages admissibles de A et B
   (à `hs` fixé) ; choisir la valeur de l'intersection la plus proche de `0.5`. Si l'intersection
   est vide, prendre le point milieu des plages et accepter le résidu **tant qu'il reste ≤
   `harmonize_pos_tol`** (fraction d'écran) ; au-delà, **renoncer** (repli).
4. Produire `V_A = view_for_placement(face_A, P)` et `V_B = view_for_placement(face_B, P)`.
   `P` étant commun et réalisable par les deux, les visages coïncident (à l'imprécision tolérée
   près). `V_A` devient `A.finish`, `V_B` devient `B.start`.

Repli : si A ou B n'a pas de visage, ou si l'harmonisation a renoncé, on garde les extrémités
**naturelles** (A.finish et B.start calculées indépendamment, comme aujourd'hui — la large
restant centrée dans ce cas).

## Extrémité large ancrée sur le visage (grief #1)

Aujourd'hui l'extrémité large est `wide_view` (centrée image). On la rend **ancrée visage** :
c'est simplement le cas « transition large » du modèle ci-dessus, avec un `hs` petit (visage
réduit), position pouvant être décentrée. Les bornes `zoom_min`/`zoom_out` et le centrage
restent ajustables dans les marges de tolérance. Une image sans visage conserve la large centrée.

## Pipeline / timing : lookahead 2

L'extrémité de fin de l'image *i* dépend de *i+1*. Pour la figer **au début** du mouvement de
*i* (mouvement propre, sans recalage), il faut que *i+1* soit déjà prête. On passe donc le
préchargement de **1 à 2 niveaux** :

- pendant l'affichage de *i-1*, on prépare *i* (niveau 1) **et** *i+1* (niveau 2) ;
- au démarrage de l'image *i*, *i* et *i+1* sont connues : on calcule `P_i` (placement conjoint
  de la nature de cette transition) et on en déduit `i.finish` et `(i+1).start`.
- `i.start` a déjà été fixé (= `P_{i-1}`) au démarrage de *i-1*. Chaque `P_i` est donc calculé
  **une seule fois**, au démarrage de *i*.
- Première image : `start` naturel (pas de prédécesseur) ; dernière du cycle : harmonisée avec
  la première du cycle suivant (via le rafraîchissement existant).

Si, malgré le lookahead, *i+1* n'est pas encore prête au démarrage de *i* (worker lent, dossier
en cours d'indexation), repli : `i.finish` naturelle, recalée si *i+1* arrive avant la fin du
mouvement (réutilise le mécanisme de recalcul déjà présent pour le redimensionnement).

> **Note d'implémentation (as-built).** Plutôt qu'un 2ᵉ emplacement de préchargement distinct,
> l'harmonisation est réalisée en **surcouche** sur les plans naturels (les rectangles
> `start`/`finish` harmonisés écrasent les rectangles naturels, conservés à part pour le
> recalcul). Le préchargement de *i+1* est déclenché **dès le début du fondu** (et non après) :
> comme le mouvement de *i* ne démarre qu'à la fin du fondu, `i.finish` est en pratique fixé
> avant le premier frame de mouvement → pas de recalage visible en régime établi. Seule la
> toute première image peut subir un ajustement unique (pas de fondu initial pour masquer le
> chargement). Si l'harmonisation échoue ou est désactivée, aucune surcouche n'est posée : le
> comportement est identique à l'existant.

### Conséquence sur le découpage worker / thread principal

Le calcul des rectangles `start`/`finish` (couplé aux voisins) **remonte au thread principal**.
Le worker continue le gros du travail (décodage, EXIF, détection, fond flou) et publie, pour
chaque image, les **données de cadrage** nécessaires au calcul des placements :

- taille image `iw,ih`, et axes libres ;
- le **visage d'harmonisation** : centre `(fcx,fcy)` et taille `(fw,fh)` en coord. image —
  c'est le visage `focus` (ou la bbox de tous si `face_focus=false`), ou rien si aucun visage ;
- les bornes de zoom `zmin_eff,zmax_eff` et les vues naturelles `tight`/`wide` (repli).

`kenburns.plan` est scindé : une partie « données de cadrage par image » (dans le worker) et des
fonctions pures `view_for_placement`, `achievable_range`, `joint_placement` (utilisées par le
thread principal au démarrage de chaque image). Champs FFI ajoutés à `DiapoJob` pour transporter
`fcx,fcy,fw,fh`, `zmin_eff,zmax_eff` (le buffer `faces[]` existe déjà pour le reste).

## Configuration

- `harmonize` (bool, défaut `true`) : active la coïncidence des visages aux transitions.
- `harmonize_zoom_tol` (défaut `0.25`) : écart relatif de taille de visage toléré avant de
  renoncer à harmoniser le zoom.
- `harmonize_pos_tol` (défaut `0.15`) : décalage de position écran toléré (fraction d'écran)
  avant de renoncer à harmoniser la position.

`zoom_max`, `zoom_min`, `zoom_out`, `margin` continuent de borner les vues ; l'harmonisation
choisit `hs`/position **dans** ces bornes (élargies par les tolérances).

## Tests (kenburns_spec, fonctions pures)

- `view_for_placement` : place bien le visage au `(sx,sy,hs)` demandé (vérif. inverse).
- `achievable_range` : plages `hs`/`sx`/`sy` correctes selon zoom et bornes image ; axe libre
  ⇒ pas de borne de position.
- `joint_placement` : deux visages → `P` commun dans l'intersection ; visages identiques ⇒
  coïncidence parfaite ; plages disjointes au-delà de la tolérance ⇒ renoncement signalé ;
  centrage choisi au plus proche de 0.5.
- Régression : image sans visage ⇒ repli naturel ; `harmonize=false` ⇒ comportement actuel.

La logique de pipeline (lookahead 2, recalage) reste dans `slideshow` (non testable hors GL),
mais s'appuie uniquement sur ces fonctions pures testées.

## Fichiers touchés

- `src/kenburns.moon` — `view_for_placement`, `achievable_range`, `joint_placement` ; extraction
  des données de cadrage ; extrémité large ancrée visage.
- `src/slideshow.moon` — préchargement lookahead 2 ; calcul de `P_i` au démarrage de chaque
  image ; application `finish`/`start` ; repli/recalage.
- `src/async.moon`, `src/worker.moon`, `ffi/jobdef.lua`, `csrc/diapo_job.h` — transport des
  données de cadrage (visage d'harmonisation + bornes de zoom).
- `src/config.moon`, `config.example.lua` — `harmonize`, `harmonize_zoom_tol`,
  `harmonize_pos_tol`.
- `tests/kenburns_spec.moon` — tests des fonctions pures.
- `README.md` — section transitions harmonisées.
