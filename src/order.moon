-- Ordonnancement des images selon une liste de priorité configurable.
-- Critères : "dossier" (répertoire parent), "exif" (date de prise de vue), "similarite"
-- (ressemblance visuelle, enchaînement plus-proche-voisin).
--
-- Modèle : la liste de priorité définit des niveaux de regroupement imbriqués. Chaque
-- critère ordonne à l'intérieur des groupes formés par les critères de priorité
-- supérieure. La similarité réordonne par enchaînement à l'intérieur de son groupe ; les
-- critères placés après elle ne servent qu'à départager des distances strictement égales.
signature = require "signature"
exif      = require "exif"

VALID = { dossier: true, exif: true, similarite: true }

-- Répertoire parent d'un chemin (chaîne vide si aucun "/").
dirname = (p) -> (p\match "^(.*)/[^/]*$") or ""

-- "YYYY:MM:DD HH:MM:SS" -> nombre YYYYMMDDHHMMSS (comparable), ou nil.
to_stamp = (s) ->
  return nil unless s
  y, mo, d, h, mi, se = s\match "(%d+):(%d+):(%d+)%s+(%d+):(%d+):(%d+)"
  return nil unless y
  tonumber(y)*10000000000 + tonumber(mo)*100000000 + tonumber(d)*1000000 +
    tonumber(h)*10000 + tonumber(mi)*100 + tonumber(se)

-- Clé temporelle d'une image : EXIF si présent, sinon mtime (via meta), sinon 0.
-- mtime epoch converti sur la même échelle YYYYMMDDHHMMSS pour rester comparable à l'EXIF.
stamp_of = (path, meta) ->
  s = to_stamp exif.datetime path
  return s if s
  m = meta and meta[path]
  if m and m.mtime
    return tonumber os.date "!%Y%m%d%H%M%S", math.floor m.mtime
  0

-- Partition stable d'`items` par clé `keyf`, groupes renvoyés dans l'ordre croissant des
-- clés ; l'ordre d'entrée est préservé à l'intérieur d'un groupe.
partition_sorted = (items, keyf) ->
  buckets = {}
  keys = {}
  for it in *items
    k = keyf it
    unless buckets[k]
      buckets[k] = {}
      keys[#keys + 1] = k
    b = buckets[k]
    b[#b + 1] = it
  table.sort keys
  [buckets[k] for k in *keys]

-- Enchaînement plus-proche-voisin sur un groupe (heuristique du voyageur de commerce).
-- Graine déterministe = item de plus petit chemin ; départage des distances égales par
-- chemin, pour un résultat reproductible quel que soit l'ordre d'entrée.
nn_chain = (items) ->
  n = #items
  return items if n <= 1
  seed = 1
  for i = 2, n
    seed = i if items[i].path < items[seed].path
  used = [false for _ = 1, n]
  used[seed] = true
  out = { items[seed] }
  last = seed
  for _ = 2, n
    best, bestd = nil, nil
    for j = 1, n
      continue if used[j]
      dj = signature.distance items[last].sig, items[j].sig
      if (not bestd) or dj < bestd or (dj == bestd and items[j].path < items[best].path)
        best, bestd = j, dj
    used[best] = true
    out[#out + 1] = items[best]
    last = best
  out

-- Ordonne récursivement un groupe selon la suite de critères `crits`.
order_group = (items, crits) ->
  return items if #items <= 1 or #crits == 0
  crit = crits[1]
  rest = [crits[i] for i = 2, #crits]
  if crit == "similarite"
    nn_chain items
  else
    keyf = crit == "dossier" and ((it) -> it.dir) or ((it) -> it.stamp)
    out = {}
    for g in *partition_sorted items, keyf
      for it in *order_group g, rest
        out[#out + 1] = it
    out

-- Normalise la liste de priorité : ne garde que les critères connus, sans doublon.
normalize = (list) ->
  return {} unless type(list) == "table"
  seen = {}
  out = {}
  for c in *list
    if VALID[c] and not seen[c]
      seen[c] = true
      out[#out + 1] = c
  out

-- Mélange Fisher-Yates en place.
shuffle = (paths, seed) ->
  math.randomseed seed or os.time!
  for i = #paths, 2, -1
    j = math.random i
    paths[i], paths[j] = paths[j], paths[i]
  paths

--------------------------------------------------------------------------------- cache
-- Cache disque des signatures, clé = chemin ; jeton d'invalidation = "taille:mtime".
-- Format : une ligne "jeton\tchemin\thex" par image. Optionnel et non bloquant.
cache_path = ->
  base = os.getenv("XDG_CACHE_HOME") or ((os.getenv("HOME") or ".") .. "/.cache")
  base .. "/diapo/signatures"

token_of = (path, meta) ->
  m = meta and meta[path]
  return nil unless m
  "#{m.size or 0}:#{math.floor m.mtime or 0}"

hex_encode = (sig) -> table.concat [string.format "%02x", b for b in *sig]
hex_decode = (hex) ->
  return nil unless hex and #hex == signature.LEN * 2
  [tonumber hex\sub(i, i + 1), 16 for i = 1, #hex, 2]

load_cache = ->
  out = {}
  f = io.open cache_path!, "r"
  return out unless f
  for line in f\lines!
    tok, path, hex = line\match "^([^\t]*)\t([^\t]*)\t(%x+)$"
    if path
      sig = hex_decode hex
      out[path] = { token: tok, sig: sig } if sig
  f\close!
  out

save_cache = (entries) ->
  path = cache_path!
  os.execute "mkdir -p '#{path\gsub "/[^/]*$", ""}' 2>/dev/null"
  f = io.open path, "w"
  return unless f
  for p, e in pairs entries
    f\write "#{e.token or ''}\t#{p}\t#{hex_encode e.sig}\n" if e.sig
  f\close!

--------------------------------------------------------------------------------- public
-- order(paths, cfg, meta) -> nouvelle liste de chemins ordonnée.
--   cfg.shuffle      : si vrai, ordre aléatoire (prioritaire).
--   cfg.order        : liste de priorité ("dossier"/"exif"/"similarite").
--   meta[path]       : { size, mtime } (facultatif) pour le repli date + le cache.
order = (paths, cfg={}, meta) ->
  list = [p for p in *paths]                        -- copie (on ne mute pas l'entrée)
  return shuffle list, cfg.seed if cfg.shuffle

  crits = normalize cfg.order
  if #crits == 0
    table.sort list                                -- repli : ordre alphabétique
    return list

  need_sig = false
  for c in *crits
    need_sig = true if c == "similarite"

  cache = need_sig and load_cache! or {}
  rl = need_sig and require("raylib") or nil

  items = {}
  for p in *list
    it = { path: p, dir: dirname(p), stamp: stamp_of(p, meta) }
    if need_sig
      tok = token_of p, meta
      hit = cache[p]
      if hit and tok and hit.token == tok
        it.sig = hit.sig
      else
        it.sig = signature.compute(rl, p) or signature.neutral!
        cache[p] = { token: tok, sig: it.sig }
    items[#items + 1] = it

  save_cache cache if need_sig

  [it.path for it in *order_group items, crits]

{ :order, :normalize, :dirname, :to_stamp, :stamp_of, :order_group, :nn_chain,
  :partition_sorted, :shuffle }
