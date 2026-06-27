-- Côté thread principal : pilote le worker de préchargement (csrc/worker.cpp).
-- Soumet un chemin, interroge l'état, et finalise (upload GPU) le résultat en une diapo.
ffi = require "ffi"
display = require "display"
rl = display.rl
require "jobdef"

ffi.cdef [[
  typedef struct DiapoWorker DiapoWorker;
  DiapoWorker * diapo_worker_start(const char *bootstrap);
  DiapoJob *    diapo_worker_job(DiapoWorker *w);
  void          diapo_worker_stop(DiapoWorker *w);
  void          diapo_membar(void);
]]

lib_path = (os.getenv("DIAPO_ROOT") or ".") .. "/lib/libfacedetection.so"
C = ffi.load lib_path

state = { worker: nil, job: nil }

-- Démarre le worker. Renvoie true si OK, false si indisponible (-> repli synchrone).
start = (bootstrap) ->
  w = C.diapo_worker_start bootstrap
  return false if w == nil
  state.worker = w
  state.job = C.diapo_worker_job w
  true

stop = ->
  if state.worker != nil
    C.diapo_worker_stop state.worker
    state.worker = nil
    state.job = nil

-- Codage du sens d'arc en entier pour le job (chaîne -> 0/1/2).
arc_dir_mode = (dir) -> switch dir
  when "toward" then 0
  when "away"   then 1
  else 2                       -- "both" (défaut)

-- Soumet une requête de préchargement. À n'appeler que si le worker est libre (idle/done).
-- `override` (optionnel) = visages normalisés [0..1] déclarés à la main (.diapo).
submit = (path, cfg, reverse, aspect, override) ->
  j = state.job
  -- chemin (copie dans le buffer fixe)
  p = path\sub 1, 4095
  ffi.copy j.path, p, #p
  j.path[#p] = 0
  j.aspect       = aspect
  j.reverse      = reverse and 1 or 0
  j.detect_width = cfg.detect_width
  j.min_score    = cfg.min_score
  j.rotate       = cfg.detect_rotated and 1 or 0
  j.margin       = cfg.margin
  j.zoom_out     = cfg.zoom_out or 1.0
  j.zoom_max     = cfg.zoom_max or 0
  j.zoom_min     = cfg.zoom_min or 0
  j.keep_eyes    = cfg.keep_eyes and 1 or 0
  j.face_focus   = (cfg.face_focus != false) and 1 or 0
  j.face_delta_max = cfg.face_delta_max or 0
  j.make_bg      = (cfg.background == "blur" and (cfg.zoom_out or 1) > 1) and 1 or 0
  j.bg_width     = cfg.bg_width
  j.bg_blur      = cfg.bg_blur
  j.arc_dir_mode = arc_dir_mode cfg.face_arc_dir
  j.img_data     = nil
  j.bg_data      = nil
  -- Override manuel des visages : écrit dans le buffer faces[] en coordonnées normalisées.
  -- Le worker convertit en pixels après chargement et saute la détection.
  if override and #override > 0
    n = math.min #override, 64
    j.override_nfaces = n
    for i = 1, n
      f = override[i]
      b = (i - 1) * 5
      j.faces[b+0], j.faces[b+1], j.faces[b+2], j.faces[b+3] = f.x, f.y, f.w, f.h
      j.faces[b+4] = f.score or 100
  else
    j.override_nfaces = 0
  C.diapo_membar!              -- release : entrées visibles avant le drapeau
  j.state        = 1           -- publie la requête en dernier

ready = -> state.job != nil and state.job.state == 2
errored = -> state.job != nil and state.job.state == 3
busy = -> state.job != nil and state.job.state == 1

reset = -> state.job.state = 0 if state.job != nil

-- Reconstruit une Image raylib à partir de champs bruts puis l'uploade en texture.
-- Libère ensuite les pixels CPU (propriété transmise par le worker).
upload = (data, w, h, fmt) ->
  img = ffi.new "Image[1]"
  img[0].data = data
  img[0].width = w
  img[0].height = h
  img[0].mipmaps = 1
  img[0].format = fmt
  tex = display.load_texture img[0]
  rl.C.UnloadImage img[0]
  tex

-- Finalise le résultat courant (thread principal, contexte GL) en une diapo, puis libère
-- le worker pour la requête suivante.
finalize = (cfg) ->
  j = state.job
  C.diapo_membar!   -- acquire : voir les résultats publiés par le worker
  tex = upload j.img_data, j.img_w, j.img_h, j.img_format
  bg = nil
  bg = upload(j.bg_data, j.bg_w, j.bg_h, j.bg_format) if j.bg_data != nil

  faces = {}
  for i = 1, j.nfaces
    b = (i - 1) * 5
    faces[i] = { x: j.faces[b+0], y: j.faces[b+1], w: j.faces[b+2], h: j.faces[b+3],
                 score: j.faces[b+4] }

  sr = { x: j.start_x, y: j.start_y, w: j.start_w, h: j.start_h }
  er = { x: j.finish_x, y: j.finish_y, w: j.finish_w, h: j.finish_h }
  plan =
    aspect: j.aspect
    start:  sr
    finish: er
    img_w:  j.img_w
    img_h:  j.img_h
    -- axes "libres" (fond visible) : pas d'écrêtage -> trajectoire lisse (voir kenburns.at)
    free_x: sr.w > j.img_w + 0.5 or er.w > j.img_w + 0.5
    free_y: sr.h > j.img_h + 0.5 or er.h > j.img_h + 0.5
    -- bosse d'arc bi-axe (calculée par le worker ; arc_sign mémorisé pour le recalcul resize)
    arc_dx: j.arc_dx
    arc_dy: j.arc_dy
    arc_sign: j.arc_sign

  -- focus = visage cadré choisi par le worker (0 = tous) ; mémorisé pour les recalculs
  -- (redimensionnement) afin que le visage cadré ne change pas en cours de diapo.
  focus = j.focus > 0 and j.focus or nil
  slide = { :tex, :bg, iw: j.img_w, ih: j.img_h, :faces, :plan, :focus,
            t0: display.time!, reverse: j.reverse != 0 }
  reset!
  slide

{ :start, :stop, :submit, :ready, :errored, :busy, :reset, :finalize }
