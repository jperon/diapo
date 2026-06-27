-- Parcours récursif d'un dossier d'images. Utilise `find` pour rester simple et rapide.
-- Renvoie (paths, meta) : la liste brute des chemins (ordre de `find`, non trié) et
-- meta[path] = { size, mtime } (utilisé pour l'ordonnancement EXIF/similarité). Le tri ou
-- le mélange est délégué au module `order`.
EXT = { jpg: true, jpeg: true, png: true, bmp: true, gif: true, webp: true }

ext_of = (path) -> (path\match "%.([^.]+)$" or "")\lower!

scan = (dir, opts={}) ->
  paths = {}
  meta = {}
  -- -L suit les liens symboliques ; -type f fichiers réguliers ; -printf : taille, mtime
  -- (epoch) et chemin, séparés par des tabulations.
  cmd = "find -L " .. ("%q")\format(dir) .. " -type f -printf '%s\\t%T@\\t%p\\n' 2>/dev/null"
  ph = io.popen cmd
  if ph
    for line in ph\lines!
      size, mtime, path = line\match "^(%d+)\t([%d.]+)\t(.*)$"
      if path and EXT[ext_of path]
        paths[#paths + 1] = path
        meta[path] = { size: tonumber(size), mtime: tonumber(mtime) }
    ph\close!
  paths, meta

{ :scan, :EXT }
