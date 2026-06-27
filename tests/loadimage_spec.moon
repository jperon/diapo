-- Test du repli de décodage (display.load_image) : un format non géré par raylib (webp)
-- doit être chargé via conversion ImageMagick. Sauté si raylib ou ImageMagick indisponibles.
passed, failed = 0, 0
ok = (cond, msg) ->
  if cond then passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{msg}\n"

have = (cmd) ->
  h = io.popen "command -v #{cmd} 2>/dev/null"
  return false unless h
  line = h\read "*l"
  h\close!
  line != nil and #line > 0

ok_display, display = pcall require, "display"
unless ok_display and (have "magick" or have "convert")
  print "  (raylib ou ImageMagick indisponible : test load_image sauté)"
  print "loadimage: 0 ok, 0 échec(s) (sauté)"
  os.exit 0

rl = require "raylib"

-- Fabrique un petit webp à partir d'une image générée par ImageMagick.
tmp = os.tmpname!
webp = tmp .. ".webp"
conv = have("magick") and "magick" or "convert"
os.execute "#{conv} -size 64x48 xc:red #{webp} 2>/dev/null"

img = display.load_image webp
ok img.width == 64 and img.height == 48,
  "webp décodé via repli (#{img.width}x#{img.height})"
rl.C.UnloadImage img if img.width > 0

-- Fichier illisible -> image vide (width 0), pas d'erreur.
bad = display.load_image (tmp .. ".inexistant")
ok bad.width == 0, "fichier illisible -> width 0 (pas de blocage)"

os.remove webp
os.remove tmp

print "loadimage: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
