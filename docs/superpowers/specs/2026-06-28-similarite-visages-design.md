# Similarité tenant compte des visages — design

Date : 2026-06-28

## Problème

Le critère d'ordonnancement `similarity` (cf. `order.moon` / `signature.moon`) ne compare que
des **vignettes couleur 8×8** (distance L1). Deux images de palettes proches sont rapprochées
même si l'une est un portrait serré et l'autre un paysage sans personne. On veut **ajuster le
score de similarité selon les visages détectés**, pour regrouper portraits avec portraits,
photos de groupe ensemble, et enchaîner des visages de disposition voisine — ce qui sert aussi
les transitions harmonisées.

## Décisions

- **Caractéristique** : nombre de visages + **visage dominant** (position et taille).
- **Combinaison** : somme pondérée `distance = couleur_norm + face_weight · face_dist`, poids
  configurable (`face_weight`, 0 = comportement actuel).
- **Détection à l'ordonnancement** : on détecte sur chaque image au démarrage (largeur de
  travail réduite), **mis en cache disque** par `taille:mtime` (comme les signatures). N'a lieu
  que si `similarity` est actif **et** `face_weight > 0`.

## Descripteur de visage (par image)

Calculé après orientation EXIF, en coordonnées **normalisées** [0,1] :

- `n` : nombre de visages (≥ seuil de score) ;
- visage **dominant** (plus grande aire) : `cx, cy` (centre / dimensions image), `h` (hauteur /
  hauteur image). Si `n = 0` : descripteur `{ n = 0 }` (pas de géométrie).

Module **pur** `src/facedesc.moon` (sans FFI, testable seul) :

- `descriptor(faces, iw, ih) -> { n, cx, cy, h }` (faces = sortie de `facedetect.detect_image`,
  coord. image) ;
- `distance(a, b) -> [0,1]` :
  - `cdiff = min(|a.n − b.n|, CAP) / CAP` (CAP = 3) ;
  - géométrie : si `a.n>0` et `b.n>0` → `geom = (dpos + dsize)/2` avec
    `dpos = hypot(Δcx, Δcy)/√2`, `dsize = min(|Δh|, 1)` ; si les deux n'ont aucun visage →
    `geom = 0` ; si l'un a un visage et pas l'autre → `geom = 1` ;
  - `distance = 0.5·cdiff + 0.5·geom` (∈ [0,1]).

## Distance combinée (order.moon)

- `couleur_norm = signature.distance(a.sig, b.sig) / (signature.LEN · 255)` (∈ [0,1]).
- `combined(a, b) = couleur_norm + face_weight · facedesc.distance(a.face, b.face)`.

`nn_chain` reçoit désormais une **fonction de distance** (au lieu d'appeler `signature.distance`
directement) ; `order_group` la propage. Avec `face_weight = 0`, `facedesc.distance` n'est pas
évaluée et l'ordre est identique à l'actuel (la normalisation couleur est monotone → mêmes
voisins).

## Détection à l'ordonnancement

`order.order` charge déjà l'image pour la signature. Pour éviter un double décodage, on **charge
une fois** par image quand la détection est requise :

1. `LoadImage` + orientation EXIF ;
2. signature via `signature.from_image(rl, img)` (nouvelle variante prenant une Image déjà
   chargée/orientée ; `signature.compute` devient : load + exif + `from_image`) ;
3. visages via `facedetect.detect_image(rl, img, { detect_width, min_score })` (détection droite,
   sans rotation, pour rester rapide) → `facedesc.descriptor`.

`facedetect` est requis **paresseusement** (comme `raylib`), uniquement si la détection est
nécessaire, afin que `order` reste requérable sans la lib native (tests purs).

### Cache disque

Format étendu, une ligne par image :

```
token \t chemin \t sigHex \t n:cx:cy:h
```

Le 4ᵉ champ (descripteur) est **optionnel** : une ligne sans lui (ancien cache) est acceptée ;
si la détection est requise et le descripteur manque (ou jeton périmé), on recalcule l'image.
L'invalidation reste `taille:mtime`.

## Configuration

- `face_weight` (défaut `0.5`) : poids des visages dans la distance de similarité. `0` =
  similarité purement couleur (et aucune détection à l'ordonnancement).

`detect_width` et `min_score` existants paramètrent la détection d'ordonnancement.

## Tests

- `facedesc` (pur, nouveau spec) : `descriptor` (dominant = plus grande aire ; normalisation ;
  `n=0`) ; `distance` (portrait vs portrait < portrait vs paysage ; symétrie ; bornes [0,1] ;
  visage↔sans-visage = pénalité max géométrie).
- `order` : `combined`/`nn_chain` avec fonction de distance ; `face_weight=0` ⇒ ordre inchangé
  (régression) ; deux images même couleur mais nombres de visages différents séparées quand
  `face_weight>0`.
- Cache : lecture tolérante d'une ligne sans descripteur ; aller-retour avec descripteur.

## Fichiers touchés

- `src/facedesc.moon` (nouveau) — descripteur + distance (pur).
- `src/signature.moon` — `from_image` (extraction), `compute` réutilise.
- `src/order.moon` — détection paresseuse + cache étendu ; distance combinée ; `nn_chain`/
  `order_group` prennent une fonction de distance.
- `src/config.moon`, `config.example.lua` — `face_weight`.
- `tests/facedesc_spec.moon` (nouveau), `tests/order_spec.moon` (distance, régression).
- `README.md` — note sur la similarité visages.
