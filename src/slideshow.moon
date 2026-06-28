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
  -- Sens du zoom de base, déterministe selon l'index (indépendant du sens de navigation).
  -- Avec `alternate` : strict zoom-in / zoom-out une image sur deux. Sans `alternate` :
  -- baseline pseudo-aléatoire (hash de l'index) plutôt que zoom-in systématique — sinon
  -- toute transition non décidée par l'harmonie (`choose_direction`) resterait en zoom-in,
  -- d'où un biais visible. `choose_direction` réoriente ensuite pour l'harmonie quand elle
  -- tranche ; cette baseline ne sert que de repli neutre.
  rev_for = (i) ->
    return i % 2 == 0 if cfg.alternate
    h = (i * 1103515245 + 12345) % 2147483648
    (math.floor(h / 65536) % 2) == 1
  wrap = (i) -> ((i - 1) % n) + 1

  use_async = async.start (os.getenv("DIAPO_ROOT") or ".") .. "/src/worker.lua"

  -- Préchargement à profondeur 2 (worker async, sinon synchrone) : `nxt` = suivante,
  -- `nxt2` = celle d'après. Connaître `nxt2` permet à `choose_direction` d'orienter `nxt`
  -- en tenant compte de SES DEUX voisines (fenêtre de 3) et d'éviter le « zig-zag ».
  nxt  = nil          -- diapo prête (suivante)
  nxt_i = nil         -- son index
  nxt2 = nil          -- diapo prête (la suivante de `nxt`)
  nxt2_i = nil        -- son index
  submitted = false   -- requête async en vol
  sub_target = nil    -- "nxt" | "nxt2" : slot que la requête en vol remplit

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

  -- Coût plafonné : `joint_placement` renvoie math.huge quand il renonce ; on borne pour qu'un
  -- côté qui renonce ne rende pas les deux orientations incomparables (l'autre côté tranche).
  HARM_CAP = 8
  capped = (c) -> math.min c, HARM_CAP

  -- Sans `alternate` : choisit le sens d'animation de l'entrante `b` pour la meilleure harmonie,
  -- en tenant compte de TROIS images quand `c` (la suivante de `b`) est connue. On évalue, pour
  -- chaque orientation de `b`, le coût du côté GAUCHE (rencontre a.finish <-> b.start) ET du côté
  -- DROIT (b.finish <-> c.start, c pouvant lui-même prendre sa meilleure orientation). Choisir
  -- le sens de `b` qui minimise la somme évite que les deux bouts de `b` réclament des cadrages
  -- contradictoires (origine du « zig-zag »). Sans `c`, on retombe sur le choix par paire.
  choose_direction = (a, b, c) ->
    return if cfg.alternate
    return unless a and b and a.plan and b.plan and a.plan.harm and b.plan.harm
    ensure_natural a.plan
    ensure_natural b.plan
    ensure_natural c.plan if c and c.plan
    has_c = c and c.plan and c.plan.harm
    -- côté gauche : a.finish (fixe) <-> départ de b
    left = (bStart) -> capped harm_cost a, a.plan.nat_finish, b, bStart
    -- côté droit : fin de b <-> départ de c, c prenant sa meilleure orientation (min des deux)
    right = (bFinish) ->
      return 0 unless has_c
      math.min (capped harm_cost b, bFinish, c, c.plan.nat_start),
        (capped harm_cost b, bFinish, c, c.plan.nat_finish)
    -- orientation courante de b : start=nat_start, finish=nat_finish ; inverse : échangés
    keep = (left b.plan.nat_start) + (right b.plan.nat_finish)
    flip = (left b.plan.nat_finish) + (right b.plan.nat_start)
    flip_direction b if flip < keep

  -- Recalcule les axes "libres" (fond visible) d'un plan d'après ses extrémités courantes.
  refresh_free = (plan) ->
    iw, ih = plan.img_w, plan.img_h
    plan.free_x = plan.start.w > iw + 0.5 or plan.finish.w > iw + 0.5
    plan.free_y = plan.start.h > ih + 0.5 or plan.finish.h > ih + 0.5

  -- Déplacement à l'écran du visage entre sa vue naturelle de rencontre `nat` et la vue
  -- harmonisée `v` (somme des écarts de position normalisés x+y). Mesure de combien le cadrage
  -- est tiré hors de sa trajectoire naturelle : sert de garde-fou de continuité.
  face_shift = (face, nat, v) ->
    math.abs((face.cx - nat.x) / nat.w - (face.cx - v.x) / v.w) +
    math.abs((face.cy - nat.y) / nat.h - (face.cy - v.y) / v.h)

  -- Repli LÉGER : quand l'harmonisation complète renonce (écart de zoom, conflit, ou mode
  -- `alternate` aux sens rigides), on décale juste un peu a.finish et b.start (déjà posées en
  -- vues naturelles) pour rapprocher la position ÉCRAN des yeux, sans toucher au zoom. Le décalage
  -- est borné par eye_align_max (continuité préservée), et la vue reste dans l'image sur les axes
  -- non débordants. Sans effet si aucune donnée d'yeux (repli sur le centre du visage).
  align_eyes = (a, b) ->
    max = cfg.eye_align_max or 0.06
    return if max <= 0
    eye_of = (plan) -> plan.eyes_c or (plan.harm and { x: plan.harm.cx, y: plan.harm.cy })
    ea, eb = (eye_of a.plan), (eye_of b.plan)
    return unless ea and eb
    va, vb = a.plan.finish, b.plan.start
    sax, say = (ea.x - va.x) / va.w, (ea.y - va.y) / va.h      -- pos écran de l'œil (sortante)
    sbx, sby = (eb.x - vb.x) / vb.w, (eb.y - vb.y) / vb.h      -- pos écran de l'œil (entrante)
    tx, ty = (sax + sbx) / 2, (say + sby) / 2                  -- cible = milieu
    toward = (t, s) -> math.max (s - max), math.min t, (s + max)  -- borne le décalage à `max`
    place = (plan, v, e, sX, sY) ->
      v.x = e.x - (toward tx, sX) * v.w
      v.y = e.y - (toward ty, sY) * v.h
      unless plan.free_x
        v.x = math.max 0, math.min v.x, plan.img_w - v.w if v.w <= plan.img_w
      unless plan.free_y
        v.y = math.max 0, math.min v.y, plan.img_h - v.h if v.h <= plan.img_h
    place a.plan, va, ea, sax, say
    place b.plan, vb, eb, sbx, sby

  -- Harmonise la transition a (sortante) -> b (entrante) : calcule un placement commun des
  -- deux visages et l'applique en surcouche (a.finish et b.start). On repart TOUJOURS des vues
  -- naturelles (annule une harmonisation précédente). On renonce à la coïncidence complète — en
  -- gardant le mouvement naturel, continu — si un visage manque, si l'écart de zoom/position
  -- dépasse les tolérances, ou si le cadrage serait tiré trop loin de sa position naturelle
  -- (harmonize_max_shift). Dans ces cas (sauf visage absent) on applique le repli léger des yeux.
  harmonize = (a, b) ->
    return unless a and b and a.plan and b.plan
    ensure_natural a.plan
    ensure_natural b.plan
    -- repli par défaut : vues naturelles (mouvement continu, pas de superposition forcée).
    -- On copie (pas d'alias avec nat_*, que flip_direction pourrait ensuite intervertir).
    copy_rect = (r) -> { k, v for k, v in pairs r }
    a.plan.finish = copy_rect a.plan.nat_finish
    b.plan.start = copy_rect b.plan.nat_start
    refresh_free a.plan
    refresh_free b.plan
    -- Tente la coïncidence complète des visages ; renvoie true si appliquée.
    full = ->
      return false unless cfg.harmonize != false and a.plan.harm and b.plan.harm
      vA, vB, ok = kenburns.joint_placement (harm_side a, a.plan.nat_finish),
        (harm_side b, b.plan.nat_start),
        display.aspect!, cfg.harmonize_zoom_tol or 0.25, cfg.harmonize_pos_tol or 0.15
      return false unless ok
      max_shift = cfg.harmonize_max_shift or 0.2
      return false if max_shift > 0 and ((face_shift a.plan.harm, a.plan.nat_finish, vA) > max_shift or
        (face_shift b.plan.harm, b.plan.nat_start, vB) > max_shift)
      a.plan.finish = vA
      b.plan.start = vB
      refresh_free a.plan
      refresh_free b.plan
      true
    align_eyes a, b unless full!

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

  -- Première image chargeable APRÈS `base` (saute les illisibles) ; renvoie index, diapo.
  prepare_after = (base) ->
    b = base
    for _ = 1, n
      i = next_index b
      cand = prepare paths[i], cfg, rev_for(i), ov(paths[i])
      return i, cand if cand
      io.stderr\write "diapo: image illisible, ignorée : #{paths[i]}\n"
      b = i
    nil, nil

  -- Remplit la file de préchargement (profondeur 2) : `nxt` puis `nxt2`. Le worker async ne
  -- traite qu'une requête à la fois (`submitted`) ; on enchaîne donc nxt puis nxt2 au fil des
  -- arrivées. `nxt2` n'est préchargée qu'en lecture automatique (pas pendant une navigation
  -- manuelle `want`, ni si moins de 3 images distinctes) : le lookahead ne sert qu'à l'harmonie.
  fill_preload = ->
    return if n < 2 or submitted or load_fail >= n
    want2 = not want and n > 2
    if use_async
      if not nxt
        i = next_index (nxt_i or ci)
        async.submit paths[i], cfg, rev_for(i), display.aspect!, ov(paths[i])
        nxt_i, sub_target, submitted = i, "nxt", true
      elseif want2 and not nxt2
        i = next_index (nxt2_i or nxt_i)
        async.submit paths[i], cfg, rev_for(i), display.aspect!, ov(paths[i])
        nxt2_i, sub_target, submitted = i, "nxt2", true
    else
      unless nxt
        nxt_i, nxt = prepare_after (nxt_i or ci)
        harm_pending = true if nxt
      if nxt and want2 and not nxt2
        nxt2_i, nxt2 = prepare_after nxt_i

  -- Avance la file d'un cran : `nxt2` devient `nxt`. Une requête en vol qui visait `nxt2`
  -- vise désormais `nxt` (c'est la même image, les indices ont juste décalé d'un cran).
  shift_queue = ->
    nxt, nxt_i = nxt2, nxt2_i
    nxt2, nxt2_i = nil, nil
    sub_target = "nxt" if sub_target == "nxt2"

  -- Vide la file de préchargement (navigation manuelle qui rompt la séquence).
  clear_queue = ->
    unload_slide nxt
    unload_slide nxt2
    nxt, nxt_i, nxt2, nxt2_i = nil, nil, nil, nil

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
    -- On ne reconstruit le plan de l'entrante QUE si le ratio d'écran a changé depuis son
    -- préchargement (sinon son départ déjà harmonisé serait écrasé). Dans ce cas seulement, on
    -- réharmonise pour restaurer ce départ. En régime normal, `to` est déjà harmonisée (comme
    -- nxt) et `cur.finish` est figée : on n'y touche pas (pas de saut en fondu).
    if to.plan.aspect != display.aspect!
      rebuild_plan to
      harmonize cur, to
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
      shift_queue!                    -- la suivante connue (nxt2) devient la nouvelle `nxt`
      begin_transition t, want, now
      want = nil
      fill_preload!
    elseif not submitted              -- worker libre : (re)soumettre la cible voulue
      clear_queue!                    -- la file séquentielle ne correspond plus à la cible
      if use_async
        nxt_i, sub_target, submitted = want, "nxt", true
        async.submit paths[want], cfg, rev_for(want), display.aspect!, ov(paths[want])
      else                            -- repli synchrone (bloque, mais worker indisponible)
        to = prepare paths[want], cfg, rev_for(want), ov(paths[want])
        if to
          begin_transition to, want, now
          want = nil
          fill_preload!
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
  fill_preload!

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
        rebuild_plan nxt2
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

    -- Réception du préchargement asynchrone (le slot rempli dépend de `sub_target`).
    if submitted
      if async.ready!
        slide = async.finalize cfg
        submitted = false
        load_fail = 0
        if sub_target == "nxt2"
          nxt2 = slide
          harm_pending = true if now <= cur_start  -- raffine l'orientation de nxt (fenêtre de 3)
        else
          nxt = slide
          harm_pending = true                      -- la suivante est prête : (ré)harmoniser
      elseif async.errored!
        submitted = false
        async.reset!                               -- libère le worker (état 3 -> 0)
        load_fail += 1
        failed_i = (sub_target == "nxt2") and nxt2_i or nxt_i
        io.stderr\write "diapo: image illisible, ignorée : #{paths[failed_i]}\n"
        -- l'index du slot reste = failed_i : fill_preload repartira de next_index(failed_i)

    service_nav now      -- fait avancer une éventuelle navigation manuelle
    fill_preload!        -- maintient la file de préchargement (nxt puis nxt2)

    -- (Ré)harmonise la transition cur -> nxt dès que les deux sont disponibles, en orientant nxt
    -- selon SES DEUX voisines quand nxt2 est connue (fenêtre de 3 -> évite le zig-zag). En régime
    -- établi, nxt est préchargée pendant le fondu, donc cur.finish est fixé avant le début du
    -- mouvement (pas de recalage visible) ; sinon l'ajustement survient dès l'arrivée de nxt.
    -- ORIENTER nxt (choose_direction) est toujours sûr : nxt n'est pas encore affichée, on ne
    -- touche pas à cur. C'est notamment vrai pour la TOUTE PREMIÈRE diapo (qui démarre sans fondu,
    -- donc cur_start est déjà passé) : sans cela, la transition 1->2 gardait le sens de baseline
    -- (souvent « aller-aller ») au lieu d'être orientée pour l'harmonie.
    -- HARMONISER (harmonize) modifie cur.finish : réservé au cas où cur n'a pas encore bougé
    -- (now <= cur_start), sinon changer sa cible en cours de mouvement ferait un saut. La 1re
    -- diapo n'est donc pas harmonisée (pas de coïncidence forcée des visages), mais son sens
    -- d'enchaînement vers la 2e est, lui, correctement choisi.
    if harm_pending and cur and nxt
      choose_direction cur, nxt, nxt2   -- oriente nxt pour la meilleure harmonie (3 images)
      harmonize cur, nxt if now <= cur_start
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
        fill_preload!
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
        if n > 1 then fill_preload! else cur_start = now
      elseif nxt
        t, ti = nxt, nxt_i
        shift_queue!      -- la suivante (nxt2) devient nxt ; une requête en vol la suit
        begin_transition t, ti, now
        fill_preload!     -- précharge la suite PENDANT le fondu (harmonisation avant le mouvement)
      -- sinon : la suivante n'est pas encore prête, on patiente (image figée sur sa fin)

  async.stop! if use_async

{ :run, :prepare }
