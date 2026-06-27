-- Orchestration du diaporama : prépare les diapos (chargement, EXIF, détection, plan
-- Ken Burns), gère le fondu enchaîné et l'alternance du sens du zoom.
ffi = require "ffi"
display   = require "display"
facedetect = require "facedetect"
kenburns  = require "kenburns"
exif      = require "exif"
async     = require "async"
rl        = display.rl

-- Convertit des visages normalisés [0..1] en coordonnées pixel (image iw×ih).
denorm_faces = (faces, iw, ih) ->
  [{ x: f.x*iw, y: f.y*ih, w: f.w*iw, h: f.h*ih, score: f.score or 100 } for f in *faces]

-- Prépare une diapo à partir d'un chemin. `override` (optionnel) = visages normalisés
-- déclarés à la main (.diapo) : s'ils existent, on saute la détection automatique.
-- Renvoie nil en cas d'échec de chargement.
prepare = (path, cfg, reverse, override) ->
  img = ffi.new "Image[1]"
  img[0] = display.load_image path
  return nil if img[0].width == 0 or img[0].height == 0

  -- Orientation EXIF
  ori = exif.orientation path
  exif.apply rl, img, ori if ori != 1

  -- Détection (sur copie réduite ; l'image d'origine reste intacte) — sauf override manuel.
  faces = if override and #override > 0
    print "diapo: visages manuels (.diapo) pour #{path} : #{#override}"
    denorm_faces override, img[0].width, img[0].height
  else
    facedetect.detect_image rl, img[0],
      detect_width: cfg.detect_width
      min_score: cfg.min_score
      rotate: cfg.detect_rotated

  -- Plusieurs visages : on en tire un seul à cadrer (sauf si face_focus désactivé). Mémorisé
  -- dans la diapo pour rester stable lors d'un recalcul (redimensionnement).
  focus = (cfg.face_focus != false and #faces > 1) and
    facedetect.weighted_index(faces, cfg.face_delta_max) or nil

  tex = display.load_texture img[0]
  iw, ih = img[0].width, img[0].height

  -- Fond flou (uniquement si le dézoom peut laisser apparaître des bords).
  bg = nil
  if cfg.background == "blur" and (cfg.zoom_out or 1) > 1
    bgimg = display.make_background_image img[0], bg_width: cfg.bg_width, bg_blur: cfg.bg_blur
    bg = display.load_texture bgimg
    rl.C.UnloadImage bgimg

  rl.C.UnloadImage img[0]   -- pixels CPU plus nécessaires une fois les textures créées

  plan = kenburns.plan iw, ih, faces,
    aspect: display.aspect!
    margin: cfg.margin
    reverse: reverse
    zoom_out: cfg.zoom_out
    zoom_max: cfg.zoom_max
    zoom_min: cfg.zoom_min
    keep_eyes: cfg.keep_eyes
    focus: focus
    arc_dir: cfg.face_arc_dir

  { :path, :tex, :bg, :iw, :ih, :faces, :plan, :focus, t0: display.time!, :reverse }

unload_slide = (s) ->
  return unless s
  display.unload_texture s.tex
  display.unload_texture s.bg if s.bg

-- `refresh` (facultatif) : fonction renvoyant une nouvelle liste ordonnée de chemins (ou
-- nil/vide si le dossier est devenu vide). Appelée en fin de cycle pour intégrer les
-- images ajoutées/supprimées sans relancer l'application.
run = (paths, cfg, refresh, overrides={}) ->
  return if #paths == 0
  n = #paths
  math.randomseed os.time! * 1000 + math.floor(os.clock! * 1000) % 1000   -- choix du visage

  -- Visages déclarés à la main (.diapo) pour un chemin, ou nil.
  ov = (path) -> overrides[path]

  -- Réactualise `paths`/`n`/`overrides` depuis `refresh()`. On ignore un résultat vide (on ne
  -- se vide pas tout seul si le dossier a été momentanément purgé).
  refresh_paths = ->
    return unless refresh
    fresh, fresh_ov = refresh!
    if fresh and #fresh > 0
      paths = fresh
      n = #paths
      overrides = fresh_ov or {}
  fade = cfg.fade
  dur  = cfg.duration
  motion_dur = dur / (cfg.speed or 1)
  arc = cfg.face_arc or 0
  debug_color = rl.Color 0, 255, 0, 255

  -- Décélération avant la transition. Quand speed>1 (rebond), le mouvement est encore en
  -- pleine course à `dur` : on déforme le temps sur une fenêtre finale pour que la vitesse
  -- tombe à 0 juste avant le gel du fondu (sinon arrêt brutal). f(u)=u+u²-u³ a f'(0)=1
  -- (continuité de vitesse à l'entrée) et f'(1)=0 (arrêt). Au-delà de `dur` : temps figé.
  slow = (cfg.bounce and motion_dur < dur) and math.min(dur, motion_dur) or 0
  warp = (el) ->
    return dur if slow > 0 and el >= dur
    return el if slow <= 0 or el <= dur - slow
    u = (el - (dur - slow)) / slow
    (dur - slow) + slow * (u + u*u - u*u*u)

  -- Progression lissée (temps déformé -> phase + rebond -> easing).
  progress = (el) -> kenburns.ease (kenburns.phase warp(el), motion_dur, cfg.bounce), cfg.easing
  -- Vitesse de progression (dérivée numérique), pour le glissé d'interruption.
  progress_vel = (el) ->
    h = 1e-3
    (progress(el + h) - progress(el - h)) / (2 * h)
  -- Sens du zoom alterné, déterministe selon l'index (indépendant du sens de navigation).
  rev_for = (i) -> cfg.alternate and (i % 2 == 0) or false
  wrap = (i) -> ((i - 1) % n) + 1

  use_async = async.start (os.getenv("DIAPO_ROOT") or ".") .. "/src/worker.lua"

  -- Préchargement de la "suivante naturelle" (worker async, sinon synchrone).
  nxt = nil          -- diapo prête
  nxt_i = nil        -- son index
  submitted = false  -- requête async en vol

  ci = 0             -- index de la diapo courante
  cur = nil
  cur_start = 0      -- instant de départ du mouvement de la diapo courante

  want = nil         -- index cible d'une navigation manuelle en attente (sinon nil)
  harm_pending = false  -- une (re)harmonisation cur<->nxt est à (re)calculer

  -- Mémorise les rectangles naturels du plan (avant toute surcouche d'harmonisation), pour
  -- pouvoir recalculer l'harmonisation à partir du cadrage d'origine (et la cible de zoom).
  ensure_natural = (plan) ->
    unless plan.nat_start
      plan.nat_start = { k, v for k, v in pairs plan.start }
      plan.nat_finish = { k, v for k, v in pairs plan.finish }
    plan

  -- Côté (sortante ou entrante) pour kenburns.joint_placement, avec sa vue naturelle de
  -- rencontre `nat`. `free` = axe où le fond flou est admis (dézoom autorisé).
  harm_side = (s, nat) ->
    blur = (cfg.zoom_out or 1) > 1
    {
      face: s.plan.harm, full_h: s.plan.full_h, zmin: s.plan.zmin, zmax: s.plan.zmax
      img_w: s.plan.img_w, img_h: s.plan.img_h, free_x: blur, free_y: blur, nat_view: nat
    }

  -- Coût d'harmonisation entre la fin de a (vue naturelle aFin) et un départ de b (vue bStart).
  harm_cost = (a, aFin, b, bStart) ->
    _, _, _, cost = kenburns.joint_placement (harm_side a, aFin), (harm_side b, bStart),
      display.aspect!, cfg.harmonize_zoom_tol or 0.25, cfg.harmonize_pos_tol or 0.15
    cost

  -- Échange début<->fin du plan d'une diapo (inverse donc le sens d'animation zoom-in/out).
  flip_direction = (s) ->
    ensure_natural s.plan
    s.plan.start, s.plan.finish = s.plan.finish, s.plan.start
    s.plan.nat_start, s.plan.nat_finish = s.plan.nat_finish, s.plan.nat_start
    s.reverse = not s.reverse

  -- Sans `alternate` : choisit le sens d'animation de l'entrante b qui s'harmonise le mieux
  -- avec la sortante a (compare le coût des deux orientations possibles de b).
  choose_direction = (a, b) ->
    return if cfg.alternate
    return unless a and b and a.plan and b.plan and a.plan.harm and b.plan.harm
    ensure_natural a.plan
    ensure_natural b.plan
    keep = harm_cost a, a.plan.nat_finish, b, b.plan.nat_start
    flip = harm_cost a, a.plan.nat_finish, b, b.plan.nat_finish
    flip_direction b if flip < keep

  -- Harmonise la transition a (sortante) -> b (entrante) : calcule un placement commun des
  -- deux visages et l'applique en surcouche (a.finish et b.start). Sans effet si désactivé,
  -- si un visage manque, ou si l'écart dépasse les tolérances (-> vues naturelles).
  harmonize = (a, b) ->
    return unless cfg.harmonize != false and a and b and a.plan.harm and b.plan.harm
    ensure_natural a.plan
    ensure_natural b.plan
    vA, vB, ok = kenburns.joint_placement (harm_side a, a.plan.nat_finish),
      (harm_side b, b.plan.nat_start),
      display.aspect!, cfg.harmonize_zoom_tol or 0.25, cfg.harmonize_pos_tol or 0.15
    return unless ok
    a.plan.finish = vA
    b.plan.start = vB
    iw, ih = a.plan.img_w, a.plan.img_h
    a.plan.free_x = a.plan.start.w > iw + 0.5 or vA.w > iw + 0.5
    a.plan.free_y = a.plan.start.h > ih + 0.5 or vA.h > ih + 0.5
    iw, ih = b.plan.img_w, b.plan.img_h
    b.plan.free_x = vB.w > iw + 0.5 or b.plan.finish.w > iw + 0.5
    b.plan.free_y = vB.h > ih + 0.5 or b.plan.finish.h > ih + 0.5

  -- Index suivant `base`, avec réactualisation de la liste au rebouclage sur la première.
  next_index = (base) ->
    if wrap(base + 1) == 1
      refresh_paths!     -- fin de cycle : récupère les images ajoutées/supprimées
      1
    else
      wrap base + 1

  -- Compteur d'échecs de chargement consécutifs (images illisibles : format non géré,
  -- fichier corrompu…). Remis à zéro dès qu'un chargement réussit. Au-delà de `n`, on
  -- renonce (toutes les images sont illisibles) pour ne pas boucler indéfiniment.
  load_fail = 0

  -- Précharge la première image chargeable APRÈS l'index `base` (saute les illisibles).
  preload_from = (base) ->
    return if nxt or submitted or n < 2
    if use_async
      nxt_i = next_index base
      async.submit paths[nxt_i], cfg, rev_for(nxt_i), display.aspect!, ov(paths[nxt_i])
      submitted = true
    else
      -- Synchrone : prepare bloque déjà ; on saute les images illisibles (prepare nil).
      b = base
      for _ = 1, n
        i = next_index b
        cand = prepare paths[i], cfg, rev_for(i), ov(paths[i])
        if cand
          nxt, nxt_i = cand, i
          harm_pending = true
          return
        io.stderr\write "diapo: image illisible, ignorée : #{paths[i]}\n"
        b = i

  preload_next = -> preload_from ci

  -- État du fondu enchaîné.
  fading = false
  fade_from = nil
  fade_from_p0 = 0     -- progression de la sortante au moment de l'interruption
  fade_from_v0 = 0     -- sa vitesse à cet instant (pour le glissé décéléré)
  fade_t0 = 0

  -- Démarre une transition de `cur` vers la diapo prête `to` (index `to_i`).
  -- La sortante ne se fige pas net : elle continue sur sa lancée en décélérant pendant le
  -- fondu (glissé). En avance naturelle la vitesse est déjà ~0, donc elle est quasi figée.
  -- La nouvelle démarre son mouvement à la fin du fondu (cur_start dans le futur).
  -- Recalcule le plan Ken Burns d'une diapo pour le ratio d'écran courant (après un
  -- redimensionnement). N'implique aucun rechargement : la texture et les visages sont
  -- indépendants du ratio ; seul le plan (rectangles début/fin) en dépend.
  rebuild_plan = (s) ->
    return unless s
    s.plan = kenburns.plan s.iw, s.ih, s.faces,
      aspect: display.aspect!
      margin: cfg.margin
      reverse: s.reverse
      zoom_out: cfg.zoom_out
      zoom_max: cfg.zoom_max
      zoom_min: cfg.zoom_min
      keep_eyes: cfg.keep_eyes
      focus: s.focus
      arc_dir: cfg.face_arc_dir
      arc_sign: s.plan and s.plan.arc_sign   -- conserve le sens d'arc tiré au premier calcul

  begin_transition = (to, to_i, now) ->
    rebuild_plan to                 -- la diapo entrante adopte le ratio d'écran courant
    harmonize cur, to               -- restaure le départ harmonisé de l'entrante (cur.finish déjà figé)
    e_i = now - cur_start
    fade_from = cur
    fade_from_p0 = progress e_i
    fade_from_v0 = progress_vel e_i
    fade_t0 = now
    fading = true
    cur = to
    ci = to_i
    cur_start = now + fade
    harm_pending = true             -- harmoniser le nouveau cur avec sa future suivante

  -- Fait progresser une navigation manuelle SANS bloquer le rendu : on confie la cible au
  -- worker et on continue d'animer l'image courante jusqu'à ce que la cible soit prête,
  -- puis on déclenche la transition (le glissé part de la vitesse réelle à cet instant).
  service_nav = (now) ->
    return unless want and not fading
    if nxt and nxt_i == want          -- cible déjà prête -> transition immédiate
      t = nxt
      nxt = nil
      begin_transition t, want, now
      want = nil
    elseif not submitted              -- worker libre : (re)soumettre la cible voulue
      if nxt and nxt_i != want
        unload_slide nxt
        nxt = nil
      if use_async
        nxt_i = want
        async.submit paths[want], cfg, rev_for(want), display.aspect!, ov(paths[want])
        submitted = true
      else                            -- repli synchrone (bloque, mais worker indisponible)
        to = prepare paths[want], cfg, rev_for(want), ov(paths[want])
        begin_transition to, want, now if to
        want = nil
    -- sinon : worker occupé sur un autre index -> on patiente (l'image courante anime)

  -- Première diapo (synchrone).
  tries = 0
  while cur == nil and tries < n
    ci = wrap ci + 1
    cur = prepare paths[ci], cfg, rev_for(ci), ov(paths[ci])
    tries += 1
  unless cur
    async.stop! if use_async
    return
  cur_start = display.time!
  preload_next!

  -- Horloge virtuelle : le temps se fige pendant les pauses (fenêtre cachée), pour que la
  -- diapo ne « saute » pas au retour. now = temps réel - durée totale passée en pause.
  paused_total = 0
  prev_real = display.time!

  -- Suivi du redimensionnement de fenêtre.
  last_w, last_h = display.screen!
  resizing = false
  resize_t = 0                 -- instant (réel) du dernier changement de taille
  resize_debounce = 0.15       -- délai de stabilisation avant réadaptation
  fadein_t0 = nil              -- fondu d'apparition après réadaptation (temps virtuel)

  -- Cadence explicite : sous Wayland natif le vsync ne bloque pas le CPU, et le WaitTime
  -- interne de raylib fait un busy-wait qui sature un cœur. On dort donc nous-mêmes le
  -- reste de chaque frame (nanosleep) pour tenir le FPS cible sans brûler le processeur.
  frame_interval = 1 / (cfg.fps or 60)
  next_frame = display.time!

  while not display.should_close!
    slack = next_frame - display.time!
    display.sleep slack if slack > 0
    next_frame += frame_interval
    next_frame = display.time! if next_frame < display.time!   -- évite la spirale après une pause

    real = display.time!
    dt = real - prev_real
    prev_real = real

    -- Détection de redimensionnement : tant que la taille change, on affiche du noir ;
    -- à la stabilisation, on recalcule les plans au nouveau ratio et on réapparaît en fondu.
    sw, sh = display.screen!
    if sw != last_w or sh != last_h
      last_w, last_h = sw, sh
      resize_t = real
      resizing = true
    if resizing
      paused_total += dt          -- on gèle l'horloge pendant l'attente (pas de saut)
      if real - resize_t >= resize_debounce
        resizing = false
        if fading                 -- annule une transition en cours
          unload_slide fade_from
          fade_from = nil
          fading = false
        rebuild_plan cur
        rebuild_plan nxt
        harm_pending = true               -- ré-harmoniser cur<->nxt au nouveau ratio
        cur_start = real - paused_total   -- relance le mouvement de la courante
        fadein_t0 = real - paused_total   -- ... avec un fondu d'apparition
      else
        display.begin_frame!
        display.clear!            -- écran noir pendant le redimensionnement
        display.end_frame!
        continue

    -- Économie de batterie : si la fenêtre est cachée (minimisée/masquée, ou sans focus si
    -- pause_unfocused), on n'affiche rien, on gèle l'horloge et on ralentit la boucle.
    hidden = (cfg.pause_hidden != false and display.hidden!) or
             (cfg.pause_unfocused and not display.focused!)
    if hidden
      paused_total += dt
      display.begin_frame!          -- continue à traiter les évènements (restauration, quit)
      display.clear!
      display.end_frame!
      display.wait 0.2              -- ~5 images/s en veille
      continue

    now = real - paused_total

    -- Touches « caractère » selon la disposition active (bépo/azerty/…), via la file de
    -- saisie Unicode : « f » bascule plein écran <-> fenêtré, « q » quitte. La réadaptation
    -- au nouveau ratio est gérée par la détection de redimensionnement ci-dessus.
    quit = false
    while true
      c = display.char_pressed!
      break if c == 0
      switch c
        when 102, 70 then display.toggle_fullscreen!   -- 'f' / 'F'
        when 113, 81 then quit = true                  -- 'q' / 'Q'
    break if quit

    -- Entrées de navigation (clavier + souris ; clic gauche = moitié gauche/droite).
    go_next = display.key_pressed(rl.KEY_RIGHT) or display.key_pressed(rl.KEY_SPACE)
    go_prev = display.key_pressed(rl.KEY_LEFT) or display.key_pressed(rl.KEY_BACKSPACE)
    if display.mouse_pressed rl.MOUSE_BUTTON_LEFT
      sw = display.screen!
      if display.mouse_x! >= sw / 2 then go_next = true else go_prev = true
    -- Écran tactile : un toucher agit comme un clic (moitié gauche/droite). L'émulation
    -- tactile->souris de SDL est désactivée (SDL_TOUCH_MOUSE_EVENTS=0), sinon le bloc souris
    -- ci-dessus se déclencherait aussi, avec une coordonnée parasite qui fausse le côté.
    if display.touch_pressed!
      sw = display.screen!
      if display.touch_x! >= sw / 2 then go_next = true else go_prev = true
    -- On enregistre la cible désirée (la transition démarrera quand elle sera prête).
    if not fading and n > 1
      want = wrap ci + 1 if go_next
      want = wrap ci - 1 if go_prev

    -- Réception du préchargement asynchrone.
    if submitted
      if async.ready!
        nxt = async.finalize cfg
        submitted = false
        load_fail = 0
        harm_pending = true                  -- l'image suivante est prête : (ré)harmoniser
      elseif async.errored!
        submitted = false
        async.reset!                         -- libère le worker (état 3 -> 0)
        load_fail += 1
        io.stderr\write "diapo: image illisible, ignorée : #{paths[nxt_i]}\n"
        -- on saute l'image défaillante et on précharge la suivante (sauf si toutes échouent)
        preload_from nxt_i if load_fail < n

    service_nav now      -- fait avancer une éventuelle navigation manuelle

    -- (Ré)harmonise la transition cur -> nxt dès que les deux sont disponibles. En régime
    -- établi, nxt est préchargée pendant le fondu, donc cur.finish est fixé avant le début du
    -- mouvement (pas de recalage visible) ; sinon, l'ajustement survient dès l'arrivée de nxt.
    if harm_pending and cur and nxt
      choose_direction cur, nxt    -- sans `alternate` : oriente nxt pour la meilleure harmonie
      harmonize cur, nxt
      harm_pending = false

    elapsed = now - cur_start

    display.begin_frame!
    display.clear!

    if fading
      -- Sortante : glissé décéléré depuis sa vitesse d'interruption jusqu'à l'arrêt, sur la
      -- durée du fondu. g(τ)=(T/2)(1-(1-τ/T)²) : g'(0)=1 (continuité de vitesse), g'(T)=0.
      T = fade
      tau = math.min (now - fade_t0), T
      glide = (T / 2) * (1 - (1 - tau / T) ^ 2)
      p_out = fade_from_p0 + fade_from_v0 * glide
      display.draw_slide fade_from, kenburns.at(fade_from.plan, p_out, arc), 255
      a = math.min 1, (now - fade_t0) / fade
      display.draw_slide cur, kenburns.at(cur.plan, progress(0), arc), math.floor a * 255
      if a >= 1
        unload_slide fade_from
        fade_from = nil
        fading = false
        preload_next!
    else
      view = kenburns.at cur.plan, progress(elapsed), arc
      -- Fondu d'apparition après réadaptation à un redimensionnement.
      alpha = 255
      if fadein_t0
        fa = (now - fadein_t0) / fade
        alpha = math.floor (math.min 1, fa) * 255
        fadein_t0 = nil if fa >= 1
      display.draw_slide cur, view, alpha
      if cfg.debug_faces
        for f in *cur.faces
          label = f.score and tostring math.floor(f.score + 0.5)
          display.draw_debug_rect view, f, debug_color, label

    display.end_frame!

    -- Avance naturelle : après le mouvement, transition vers la suivante (sauf si une
    -- navigation manuelle est en cours de service, qui a la priorité).
    if not fading and not want and elapsed >= dur
      if n == 1
        -- Une seule image : fin de « cycle » à chaque passage -> on tente un rafraîchissement
        -- (un dossier démarré à 1 image peut ainsi récupérer les ajouts), sinon on relance.
        refresh_paths!
        if n > 1 then preload_next! else cur_start = now
      elseif nxt
        t, ti = nxt, nxt_i
        nxt = nil
        nxt_i = nil
        begin_transition t, ti, now
        preload_next!     -- précharge la suivante PENDANT le fondu (harmonisation avant le mouvement)
      -- sinon : la suivante n'est pas encore prête, on patiente (image figée sur sa fin)

  async.stop! if use_async

{ :run, :prepare }
