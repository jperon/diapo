-- Sélecteur de dossier le plus compatible possible : essaie successivement les boîtes de
-- dialogue GUI courantes (indépendantes du bureau) et utilise la première disponible.
-- Aucune dépendance compilée ; tout passe par io.popen.

has_command = (name) ->
  ph = io.popen "command -v #{name} 2>/dev/null"
  return false unless ph
  line = ph\read "*l"
  ph\close!
  line and #line > 0

TITLE = "diapo — choisir un dossier de photos"

-- Outils testés dans l'ordre, avec la commande renvoyant un chemin de dossier sur stdout.
backends = {
  { name: "zenity",     cmd: "zenity --file-selection --directory --title=#{('%q')\format TITLE}" }
  { name: "qarma",      cmd: "qarma --file-selection --directory --title=#{('%q')\format TITLE}" }
  { name: "matedialog", cmd: "matedialog --file-selection --directory --title=#{('%q')\format TITLE}" }
  { name: "yad",        cmd: "yad --file --directory --title=#{('%q')\format TITLE}" }
  { name: "kdialog",    cmd: "kdialog --title #{('%q')\format TITLE} --getexistingdirectory \"${HOME:-/}\"" }
  { name: "Xdialog",    cmd: "Xdialog --stdout --title #{('%q')\format TITLE} --dselect \"${HOME:-/}\" 0 0" }
}

-- Ouvre un sélecteur et renvoie le chemin choisi, ou nil (annulation ou aucun outil).
-- Second retour : false si AUCUN outil n'est disponible (pour message d'aide).
pick_directory = ->
  available = false
  for b in *backends
    continue unless has_command b.name
    available = true
    ph = io.popen b.cmd
    continue unless ph
    path = ph\read "*l"
    ph\close!
    if path and #path > 0
      -- certains outils ajoutent un '/' final ; on le retire (sauf racine)
      path = path\gsub "/+$", "" if #path > 1
      return path, true
    return nil, true   -- l'outil s'est lancé mais l'utilisateur a annulé
  nil, available

{ :pick_directory, :has_command }
