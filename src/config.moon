-- Configuration du diaporama : valeurs par défaut + fusion avec un fichier Lua optionnel.
defaults =
  duration:    7.0      -- secondes d'affichage par image (mouvement Ken Burns)
  fade:        1.2      -- durée du fondu entre images (s)
  fullscreen:  true
  window_width:  1280   -- taille de la fenêtre en mode fenêtré (redimensionnable ensuite)
  window_height: 720
  fps:         60
  pause_hidden:    true   -- met le rendu en pause si la fenêtre est minimisée/masquée
  pause_unfocused: false  -- pause aussi quand la fenêtre n'a pas le focus (économie agressive)
  shuffle:     true     -- ordre aléatoire
  recursive:   true
  detect_width: 480     -- largeur de travail pour la détection (px)
  min_score:   70       -- seuil de confiance des visages
  margin:      0.35     -- marge autour des visages pour le cadrage serré
  alternate:   true     -- alterne zoom-in / zoom-out d'une image à l'autre
  debug_faces: false    -- dessine les rectangles de visages détectés
  keep_eyes:   true     -- garde toujours les yeux des sujets dans la vue
  speed:       1.0      -- vitesse de l'effet (1 = une traversée par durée d'affichage)
  bounce:      true     -- aller-retour si l'affichage dure plus que le mouvement
  easing:      2.0      -- accél./décél. : 1 = linéaire, 2 = doux, >2 = marqué
  face_arc:    0.12     -- bosse verticale du cadrage (sujet remonte puis redescend) ; 0 = off
  zoom_out:    1.0      -- >1 : autorise un dézoom au-delà de l'image (ex. 1.3)
  zoom_max:    0.0      -- magnification max de la vue serrée (0 = pas de limite)
  zoom_min:    0.0      -- magnification min de la vue large (plancher ; 0 = pas de plancher)
  background:  "blur"   -- fond quand l'image ne couvre pas l'écran : "blur" | "black"
  bg_width:    320      -- largeur de l'image de fond avant flou (px)
  bg_blur:     12       -- intensité du flou gaussien du fond

-- Existence d'un fichier lisible.
file_exists = (p) ->
  return false unless p
  f = io.open p, "r"
  return false unless f
  f\close!
  true

-- Chemin de config par défaut quand aucun n'est passé en argument :
--   1. ./config.lua dans le dossier courant ;
--   2. à défaut, $XDG_CONFIG_HOME/diapo/config.lua puis ~/.local/share/diapo/config.lua.
default_path = ->
  return "config.lua" if file_exists "config.lua"
  home = os.getenv "HOME"
  if home
    p = "#{home}/.local/share/diapo/config.lua"
    return p if file_exists p
  nil

-- Charge un fichier de config Lua (renvoyant une table) et le fusionne aux défauts.
-- Sans chemin explicite, on cherche un fichier de config par défaut (default_path).
load = (path) ->
  cfg = {k, v for k, v in pairs defaults}
  explicit = path != nil
  path = default_path! unless explicit
  if path
    chunk = loadfile path
    if chunk
      ok, t = pcall chunk
      if ok and type(t) == "table"
        cfg[k] = v for k, v in pairs t
        print "diapo: config #{path}"
      else
        io.stderr\write "diapo: config illisible (#{path}), valeurs par défaut\n"
    elseif explicit
      io.stderr\write "diapo: config introuvable (#{path}), valeurs par défaut\n"
  cfg

{ :load, :defaults, :default_path }
