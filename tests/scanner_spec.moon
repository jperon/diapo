-- Tests du scanner : collecte d'images + résolution des overrides .diapo.
scanner = require "scanner"

passed, failed = 0, 0
ok = (cond, msg) ->
  if cond then passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{msg}\n"

-- Arborescence temporaire : racine avec une image + un .diapo, et un sous-dossier avec sa
-- propre image, couverte à la fois par le .diapo racine et par un .diapo plus profond.
root = os.tmpname!
os.remove root                       -- tmpname crée un fichier ; on veut un dossier
os.execute "mkdir -p #{root}/sous"
write = (path, content) ->
  f = io.open path, "w"
  f\write content
  f\close!

-- Images (contenu indifférent, seules les extensions comptent pour le scan).
write "#{root}/a.jpg", "x"
write "#{root}/sous/b.jpg", "x"

-- .diapo racine : couvre a.jpg, et sous/b.jpg (visage A).
write "#{root}/.diapo", [[
return {
  ["a.jpg"]      = { { x = 0.10, y = 0.10, w = 0.20, h = 0.20 } },
  ["sous/b.jpg"] = { { x = 0.00, y = 0.00, w = 0.10, h = 0.10 } },
  ["bad.jpg"]    = { { x = 2.0, y = 0.0, w = 0.1, h = 0.1 } },  -- hors [0,1] -> ignoré
}
]]
-- .diapo plus profond : redéfinit sous/b.jpg (visage B) -> doit gagner.
write "#{root}/sous/.diapo", [[
return {
  ["b.jpg"] = { { x = 0.50, y = 0.50, w = 0.10, h = 0.10 } },
}
]]

paths, meta, overrides = scanner.scan root

-- Deux images détectées (les .diapo ne comptent pas comme images).
ok #paths == 2, "deux images scannées (obtenu #{#paths})"

a_ov = overrides["#{root}/a.jpg"]
ok a_ov and #a_ov == 1, "a.jpg : un visage d'override"
ok a_ov and math.abs(a_ov[1].x - 0.10) < 1e-9, "a.jpg : coordonnées normalisées conservées"
ok a_ov and a_ov[1].score == 100, "score par défaut = 100"

-- bad.jpg : entrée invalide -> aucune override.
ok overrides["#{root}/bad.jpg"] == nil, "entrée invalide (hors [0,1]) ignorée"

-- sous/b.jpg : le .diapo le plus profond (visage B en 0.5,0.5) l'emporte sur le racine.
b_ov = overrides["#{root}/sous/b.jpg"]
ok b_ov and #b_ov == 1, "sous/b.jpg : un visage d'override"
ok b_ov and math.abs(b_ov[1].x - 0.50) < 1e-9, "sous/b.jpg : le .diapo le plus profond gagne"

-- Clé en chemin absolu : prise telle quelle (pas de concaténation au dossier du .diapo).
write "#{root}/abs.jpg", "x"
write "#{root}/.diapo", "return { [\"#{root}/abs.jpg\"] = { { x=0.1, y=0.1, w=0.1, h=0.1 } } }"
_, _, ov_abs = scanner.scan root
ok ov_abs["#{root}/abs.jpg"], "clé en chemin absolu reconnue"

os.execute "rm -rf #{root}"

print "scanner: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
