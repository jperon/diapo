-- Parcours récursif d'un dossier d'images. Utilise `find` (POSIX) pour rester simple
-- et rapide ; renvoie une liste de chemins, triée ou mélangée.
EXT = { jpg: true, jpeg: true, png: true, bmp: true, gif: true, webp: true }

ext_of = (path) -> (path\match "%.([^.]+)$" or "")\lower!

scan = (dir, opts={}) ->
  paths = {}
  -- -L suit les liens symboliques ; -type f fichiers réguliers.
  cmd = "find -L " .. ("%q")\format(dir) .. " -type f 2>/dev/null"
  ph = io.popen cmd
  if ph
    for line in ph\lines!
      paths[#paths+1] = line if EXT[ext_of line]
    ph\close!

  if opts.shuffle
    math.randomseed opts.seed or os.time!
    for i = #paths, 2, -1
      j = math.random i
      paths[i], paths[j] = paths[j], paths[i]
  else
    table.sort paths

  paths

{ :scan, :EXT }
