# Ordre des images par similarité — design

## Objectif

Ajouter un mode d'ordonnancement des images au-delà de l'actuel
alphabétique/aléatoire, pour une succession plus « logique ». Trois critères,
combinables selon une **liste de priorité configurable** :

- `dossier` — répertoire parent
- `exif` — date de prise de vue (EXIF `DateTimeOriginal`, repli mtime)
- `similarite` — ressemblance visuelle (enchaînement de proche en proche)

## Modèle de composition

La liste de priorité définit des **niveaux de regroupement imbriqués**. Chaque
critère partitionne/ordonne à l'intérieur des groupes formés par les critères de
priorité supérieure. La **similarité**, où qu'elle soit dans la liste, réordonne
les images à l'intérieur du groupe défini par les critères placés avant elle, par
enchaînement plus-proche-voisin ; les critères placés après elle ne servent qu'à
départager des distances strictement égales.

| Priorité | Résultat |
|---|---|
| `dossier, exif, similarite` | Par dossier → par date ; similarité départage les dates égales (≈ chronologique). |
| `dossier, similarite, exif` | Par dossier → parcours visuellement fluide de chaque dossier. |
| `similarite, dossier, exif` | Grande chaîne visuelle sur tout le corpus, dossiers ignorés. |

## Signature visuelle

Vignette couleur **8×8** : `load → applique orientation EXIF → ImageResize 8×8 RGB8`
→ 192 octets. Distance = somme des écarts absolus composante par composante (L1).
Capte palette + composition grossière → transitions d'ambiance douces. Réutilise
`ImageResize` déjà présent dans `facedetect`.

## Algorithme d'ordre

Enchaînement plus-proche-voisin (heuristique TSP) par groupe : graine
déterministe (première image du groupe par chemin), puis ajout répété de l'image
non placée la plus proche de la dernière. O(n²) par groupe — négligeable jusqu'à
quelques milliers d'images.

## Architecture / modules

- `scanner.moon` : ne fait plus que **découvrir** les fichiers (liste brute de
  chemins). La logique tri/shuffle en sort.
- `order.moon` (nouveau) : `order(paths, cfg) -> paths ordonnés`. Lecture des
  critères, signatures (+ cache), regroupement imbriqué, enchaînement.
- `signature.moon` (nouveau) : `compute(rl, path) -> sig`, `distance(a, b)`.
- `exif.moon` : ajout de `datetime(path)` (tag 0x9003) à côté d'`orientation`.
- `main.moon` : options CLI/config ; appelle `order.order`.

## Configuration

```lua
order = { "dossier", "exif", "similarite" },  -- liste = priorité décroissante
```

- Valeurs : `"dossier"`, `"exif"`, `"similarite"` (toutes optionnelles).
- `shuffle = true` (défaut actuel) reste prioritaire → aléatoire ; `order` n'agit
  que si `shuffle` est faux/absent.
- L'alphabétique actuel = `order = { "dossier" }`.
- CLI : `--order dossier,exif,similarite` surclasse la config et implique
  `--no-shuffle`.

## Cache des signatures

- Fichier unique sous `~/.cache/diapo/signatures` (ou `$XDG_CACHE_HOME`), une
  ligne `clé\tsignature_hex` par image.
- Clé d'invalidation = `taille:mtime` du fichier. Absent/différent → recalcul.
- Optionnel et non bloquant : cache illisible/non inscriptible → recalcul
  silencieux.

## Flux `order.order(paths, cfg)`

1. Pré-passe signatures **seulement si** `similarite` est demandé (sinon aucune
   image décodée).
2. Calcul des clés sortables (`dossier`, `exif`).
3. Regroupement imbriqué récursif selon la liste de priorité ; `similarite` →
   enchaînement plus-proche-voisin.
4. Concaténation → liste finale.

## Gestion d'erreurs / cas limites

- Image illisible en pré-passe → signature neutre + avertissement stderr ;
  conservée dans la liste.
- EXIF date absente → mtime ; les deux absents → 0 (tête de groupe, stable).
- `order` vide/inconnu → repli alphabétique actuel.
- Groupe de 0 ou 1 élément → renvoyé tel quel.

## Tests

- `signature` : distance(x, x) = 0 ; symétrie ; aplats opposés → distance grande.
- `order` : jeu synthétique de signatures (sans décodage) → enchaînement NN ;
  les 3 permutations du tableau ; déterminisme.
- `exif.datetime` : JPEG de `testdata` avec/sans tag.
