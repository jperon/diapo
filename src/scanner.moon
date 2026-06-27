-- Parcours récursif d'un dossier d'images. Utilise `find` pour rester simple et rapide.
-- Renvoie (paths, meta, overrides) : la liste brute des chemins (ordre de `find`, non trié),
-- meta[path] = { size, mtime } (utilisé pour l'ordonnancement EXIF/similarité), et
-- overrides[path] = { {x,y,w,h,score}, ... } : visages déclarés manuellement (coordonnées
-- normalisées [0..1]) dans les fichiers `.diapo`. Le tri/mélange est délégué à `order`.
-- Formats reconnus. Ceux que raylib ne décode pas nativement (webp, avif, jp2, heic…) sont
-- pris en charge via le repli de conversion externe (voir display.load_image).
EXT = {
  jpg: true, jpeg: true, png: true, bmp: true, gif: true, tga: true,
  webp: true, avif: true, heic: true, heif: true,
  jp2: true, j2k: true, jpf: true, jpx: true, tif: true, tiff: true
}

ext_of = (path) -> (path\match "%.([^.]+)$" or "")\lower!
basename = (path) -> path\match "([^/]+)$" or path
dirname = (path) ->
  d = path\match "^(.*)/[^/]+$"
  d or "."
-- Profondeur d'un chemin = nombre de séparateurs (sert à départager les .diapo imbriqués).
depth_of = (path) ->
  n = 0
  n += 1 for _ in path\gmatch "/"
  n

-- Valide un visage normalisé brut ; renvoie une copie nettoyée ou nil si invalide.
valid_face = (f) ->
  return nil unless type(f) == "table"
  x, y, w, h = tonumber(f.x), tonumber(f.y), tonumber(f.w), tonumber(f.h)
  return nil unless x and y and w and h
  return nil unless x >= 0 and y >= 0 and w > 0 and h > 0 and (x + w) <= 1.0001 and (y + h) <= 1.0001
  { :x, :y, :w, :h, score: tonumber(f.score) or 100, normalized: true }

-- Charge un fichier `.diapo` (Lua renvoyant une table) en bac à sable (environnement vide).
-- Renvoie une table { chemin_absolu -> liste de visages valides } ou {} en cas d'échec.
load_diapo = (diapo_path) ->
  chunk, err = loadfile diapo_path
  unless chunk
    io.stderr\write "diapo: .diapo illisible (#{err})\n"
    return {}
  setfenv chunk, {} if setfenv          -- sandbox (Lua 5.1 / LuaJIT)
  ok, t = pcall chunk
  unless ok and type(t) == "table"
    io.stderr\write "diapo: .diapo invalide (#{diapo_path})\n"
    return {}
  base = dirname diapo_path
  out = {}
  nkeys = 0
  for key, faces in pairs t
    continue unless type(key) == "string" and type(faces) == "table"
    -- Clé absolue (commençant par /) prise telle quelle ; sinon relative au dossier du .diapo.
    abs = key\sub(1,1) == "/" and key or "#{base}/#{key}"
    clean = {}
    for f in *faces
      vf = valid_face f
      if vf then clean[#clean+1] = vf
      else io.stderr\write "diapo: visage invalide ignoré pour #{key} (#{diapo_path})\n"
    if #clean > 0
      out[abs] = clean
      nkeys += 1
    else
      io.stderr\write "diapo: #{key} sans visage valide, ignoré (#{diapo_path})\n"
  print "diapo: .diapo chargé #{diapo_path} (#{nkeys} image(s) ciblée(s))"
  out

scan = (dir, opts={}) ->
  paths = {}
  meta = {}
  diapos = {}     -- chemins des .diapo rencontrés
  -- -L suit les liens symboliques ; -type f fichiers réguliers ; -printf : taille, mtime
  -- (epoch) et chemin, séparés par des tabulations.
  cmd = "find -L " .. ("%q")\format(dir) .. " -type f -printf '%s\\t%T@\\t%p\\n' 2>/dev/null"
  ph = io.popen cmd
  if ph
    for line in ph\lines!
      size, mtime, path = line\match "^(%d+)\t([%d.]+)\t(.*)$"
      continue unless path
      if basename(path) == ".diapo"
        diapos[#diapos + 1] = path
      elseif EXT[ext_of path]
        paths[#paths + 1] = path
        meta[path] = { size: tonumber(size), mtime: tonumber(mtime) }
    ph\close!

  -- Fusion des overrides : on traite les .diapo du moins profond au plus profond, afin que
  -- l'entrée du .diapo le plus proche (le plus profond) écrase celle d'un .diapo ancêtre.
  table.sort diapos, (a, b) -> depth_of(a) < depth_of(b)
  overrides = {}
  for dp in *diapos
    for abs, faces in pairs load_diapo dp
      overrides[abs] = faces

  -- Récapitulatif : combien d'images scannées sont couvertes, et signalement des clés
  -- d'override qui ne correspondent à aucune image trouvée (faute de frappe / mauvais chemin).
  if next overrides
    known = {p, true for p in *paths}
    matched, orphan = 0, 0
    for abs in pairs overrides
      if known[abs] then matched += 1
      else
        orphan += 1
        io.stderr\write "diapo: override sans image correspondante : #{abs}\n"
    print "diapo: overrides .diapo : #{matched} image(s) couverte(s)" .. (orphan > 0 and ", #{orphan} clé(s) orpheline(s)" or "")

  paths, meta, overrides

{ :scan, :EXT }
