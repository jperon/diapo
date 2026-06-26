-- Point d'entrée du diaporama Ken Burns + détection de visage.
-- Usage : luajit src/main.lua <dossier> [--config fichier.lua] [options]
config    = require "config"
scanner   = require "scanner"
display   = require "display"
slideshow = require "slideshow"
picker    = require "picker"

usage = -> io.stderr\write [[
diapo — diaporama Ken Burns guidé par les visages

Usage:
  diapo [<dossier>] [options]

Sans <dossier>, un sélecteur de dossier graphique s'ouvre (zenity/kdialog/qarma/yad…).

Options:
  --config <fichier>   fichier de configuration Lua
                       (défaut : ./config.lua, sinon ~/.local/share/diapo/config.lua)
  --window             mode fenêtré (au lieu du plein écran)
  --no-shuffle         ordre alphabétique au lieu d'aléatoire
  --debug-faces        affiche les rectangles des visages détectés
  --keep-eyes / --no-keep-eyes  garder les yeux dans la vue (défaut : oui)
  --zoom-out <f>       dézoom max au-delà de l'image (ex. 1.3 ; fond flou)
  --zoom-max <f>       magnification max de la vue serrée (0 = pas de limite)
  --zoom-min <f>       magnification min de la vue large (plancher)
  --no-blur            fond noir au lieu du fond flou
  --speed <f>          vitesse de l'effet (1 = une traversée par durée)
  --no-bounce          désactive l'aller-retour
  --easing <f>         accél./décél. (1 = linéaire, 2 = doux, >2 = marqué)
  --duration <s>       durée par image
  --fade <s>           durée du fondu (ajoutée à la durée)
  --pause-unfocused    met en pause aussi quand la fenêtre perd le focus
  --help               cette aide
]]

parse_args = (argv) ->
  opts = { dir: nil, config: nil, overrides: {} }
  i = 1
  while i <= #argv
    a = argv[i]
    switch a
      when "--help", "-h"
        usage!
        os.exit 0
      when "--config"
        i += 1
        opts.config = argv[i]
      when "--window"      then opts.overrides.fullscreen = false
      when "--no-shuffle"  then opts.overrides.shuffle = false
      when "--debug-faces" then opts.overrides.debug_faces = true
      when "--keep-eyes"   then opts.overrides.keep_eyes = true
      when "--no-keep-eyes" then opts.overrides.keep_eyes = false
      when "--no-blur"     then opts.overrides.background = "black"
      when "--no-bounce"   then opts.overrides.bounce = false
      when "--pause-unfocused" then opts.overrides.pause_unfocused = true
      when "--speed"
        i += 1
        opts.overrides.speed = tonumber argv[i]
      when "--easing"
        i += 1
        opts.overrides.easing = tonumber argv[i]
      when "--zoom-out"
        i += 1
        opts.overrides.zoom_out = tonumber argv[i]
      when "--zoom-max"
        i += 1
        opts.overrides.zoom_max = tonumber argv[i]
      when "--zoom-min"
        i += 1
        opts.overrides.zoom_min = tonumber argv[i]
      when "--duration"
        i += 1
        opts.overrides.duration = tonumber argv[i]
      when "--fade"
        i += 1
        opts.overrides.fade = tonumber argv[i]
      else
        if a\match "^%-%-"
          io.stderr\write "diapo: option inconnue #{a}\n"
          os.exit 1
        else
          opts.dir = a
    i += 1
  opts

main = (argv) ->
  opts = parse_args argv
  -- Sans dossier en argument : on ouvre un sélecteur de dossier (multi-bureau).
  unless opts.dir
    dir, available = picker.pick_directory!
    if dir
      opts.dir = dir
    elseif not available
      io.stderr\write "diapo: aucun sélecteur de dossier trouvé (installez zenity, kdialog, qarma ou yad)\n\n"
      usage!
      os.exit 1
    else
      os.exit 0   -- l'utilisateur a annulé le sélecteur

  cfg = config.load opts.config
  cfg[k] = v for k, v in pairs opts.overrides

  paths = scanner.scan opts.dir, shuffle: cfg.shuffle
  if #paths == 0
    io.stderr\write "diapo: aucune image trouvée dans #{opts.dir}\n"
    os.exit 1
  print "diapo: #{#paths} image(s), démarrage…"

  display.init fullscreen: cfg.fullscreen, fps: cfg.fps, title: "diapo",
    width: cfg.window_width, height: cfg.window_height
  sw, sh = display.screen!
  orient = sw >= sh and "paysage" or "portrait"
  print "diapo: écran #{sw}×#{sh} (#{orient})"
  ok, err = pcall slideshow.run, paths, cfg
  display.close!
  unless ok
    io.stderr\write "diapo: erreur — #{err}\n"
    os.exit 1

main { ... }
