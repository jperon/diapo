-- Exemple de configuration diapo. Copier en config.lua et lancer :
--   ./diapo <dossier> --config config.lua
return {
  duration     = 7.0,    -- secondes d'affichage par image
  fade         = 1.2,    -- durée du fondu enchaîné (s)
  fullscreen   = true,   -- false = fenêtré (fenêtre redimensionnable)
  window_width  = 1280,  -- taille initiale de la fenêtre en mode fenêtré
  window_height = 720,
  fps          = 60,
  pause_hidden    = true,  -- met le rendu en pause si la fenêtre est minimisée/masquée
  pause_unfocused = false, -- pause aussi quand la fenêtre n'a pas le focus
  shuffle      = true,   -- ordre aléatoire
  recursive    = true,
  detect_width = 480,    -- largeur de travail pour la détection (px) ; ↑ = + précis, − rapide
  min_score    = 70,     -- seuil de confiance des visages (0..100)
  margin       = 0.35,   -- marge autour des visages pour le cadrage serré
  alternate    = true,   -- alterne zoom-in / zoom-out d'une image à l'autre
  debug_faces  = false,  -- dessine les rectangles des visages détectés
  keep_eyes    = true,   -- garde toujours les yeux des sujets dans la vue
  speed        = 1.0,    -- vitesse de l'effet (1 = une traversée par durée d'affichage)
  bounce       = true,   -- aller-retour si l'affichage dure plus que le mouvement
  easing       = 2.0,    -- accél./décél. : 1 = linéaire, 2 = doux, >2 = marqué
  face_arc     = 0.12,   -- bosse verticale (le sujet remonte puis redescend) ; 0 = désactivé
  zoom_out     = 1.0,    -- >1 : autorise un dézoom au-delà de l'image (ex. 1.3)
  zoom_max     = 0.0,    -- magnification max de la vue serrée (0 = pas de limite)
  zoom_min     = 0.0,    -- magnification min de la vue large (plancher ; 0 = pas de plancher)
  background   = "blur", -- fond hors image : "blur" (flou) ou "black" (noir)
  bg_width     = 320,    -- largeur de l'image de fond avant flou (px)
  bg_blur      = 12,     -- intensité du flou gaussien du fond
}
