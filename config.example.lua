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
  shuffle      = true,   -- ordre aléatoire (prioritaire ; mettre false pour utiliser `order`)
  -- Ordonnancement quand shuffle = false. Liste de priorité décroissante parmi :
  --   "folder"     : regroupe par répertoire parent
  --   "exif"       : trie par date de prise de vue (EXIF, repli date du fichier)
  --   "similarity" : enchaîne les images visuellement proches (vignette couleur 8×8)
  -- La similarité réordonne à l'intérieur des groupes définis par les critères qui la
  -- précèdent. Exemples : {"folder","exif"} ≈ chronologique par dossier ;
  -- {"folder","similarity"} = parcours visuellement fluide de chaque dossier.
  -- (Les anciens noms "dossier"/"similarite" restent acceptés.)
  order        = { "folder", "similarity" },
  recursive    = true,
  face_weight  = 0.5,    -- poids des visages dans la similarité (0 = couleur seule, aucune
                         -- détection à l'ordonnancement) ; n'agit que si "similarity" est utilisé
  detect_width = 480,    -- largeur de travail pour la détection (px) ; ↑ = + précis, − rapide
  min_score    = 70,     -- seuil de confiance des visages (0..100)
  detect_rotated = false,-- true : détecte aussi sur ±90° même quand un visage est déjà
                         -- trouvé à l'endroit (photos d'orientations mêlées ; ~3× plus lent)
  margin       = 0.35,   -- marge autour des visages pour le cadrage serré
  alternate    = true,   -- alterne zoom-in / zoom-out d'une image à l'autre ; false = le sens
                         -- de chaque image est choisi pour la meilleure harmonie des visages
  debug_faces  = false,  -- dessine les rectangles des visages détectés
  keep_eyes    = true,   -- garde toujours les yeux des sujets dans la vue
  face_focus   = true,   -- si plusieurs visages : zoome sur un seul, tiré au hasard à chaque
                         -- passage et pondéré par le score de détection (les visages les plus
                         -- sûrs sortent plus souvent) ; false = englobe tous (photo de groupe)
  face_delta_max = 9,    -- écart de score maximal sous le meilleur visage pour rester éligible
                         -- au tirage (0 = illimité ; ex. 9 : meilleur à 93 -> 80 est ignoré)
  speed        = 1.0,    -- vitesse de l'effet (1 = une traversée par durée d'affichage)
  bounce       = true,   -- aller-retour si l'affichage dure plus que le mouvement
  easing       = 2.0,    -- accél./décél. : 1 = linéaire, 2 = doux, >2 = marqué
  face_arc     = 0.12,   -- amplitude de la bosse (le cadrage dévie puis revient) ; 0 = désactivé
  face_arc_dir = "both", -- sens de la bosse selon la position du sujet : "toward" (vers le
                         -- sujet), "away" (à l'opposé) ou "both" (tiré au hasard à chaque image)
  harmonize    = true,   -- fait coïncider les visages de deux images consécutives pendant le
                         -- fondu (vues de fin/début calculées conjointement) ; false = indép.
  harmonize_zoom_tol = 0.25, -- écart relatif de taille de visage toléré avant de renoncer
  harmonize_pos_tol  = 0.15, -- décalage de position écran toléré (fraction d'écran)
  harmonize_max_shift = 0.2, -- déplacement écran max d'un visage hors de sa position naturelle
                             -- avant de renoncer (préserve la continuité) ; 0 = désactivé
  eye_align_max = 0.06,      -- repli quand l'harmonisation renonce (ou mode alternate) : décalage
                             -- écran max pour rapprocher les yeux des deux images ; 0 = off
  zoom_out     = 1.0,    -- >1 : autorise un dézoom au-delà de l'image (ex. 1.3)
  zoom_max     = 0.0,    -- magnification max de la vue serrée (0 = pas de limite)
  zoom_min     = 0.0,    -- magnification min de la vue large (plancher ; 0 = pas de plancher)
  background   = "blur", -- fond hors image : "blur" (flou) ou "black" (noir)
  bg_width     = 320,    -- largeur de l'image de fond avant flou (px)
  bg_blur      = 12,     -- intensité du flou gaussien du fond
}
