-- Bootstrap exécuté dans le lua_State du thread worker (lancé par csrc/worker.cpp).
-- Boucle : attend une requête (job.state==1), effectue tout le travail CPU lourd
-- (chargement, EXIF, détection, plan Ken Burns, fond flou), puis publie le résultat
-- (job.state==2). Aucun appel GPU ici : l'upload des textures reste au thread principal.
ffi = require "ffi"

root = os.getenv("DIAPO_ROOT") or "."
package.path = "#{root}/src/?.lua;#{root}/ffi/?.lua;#{package.path}"

require "jobdef"                 -- définit le type DiapoJob
ffi.cdef "unsigned int usleep(unsigned int usec);"

rl         = require "raylib"
facedetect = require "facedetect"
kenburns   = require "kenburns"
exif       = require "exif"
display    = require "display"   -- pour make_background_image (CPU uniquement)

-- DIAPO_JOB est une lightuserdata posée par le C : pointeur sur la struct partagée.
job = ffi.cast "DiapoJob *", DIAPO_JOB

-- Amorçage du tirage aléatoire (choix du visage cadré quand il y en a plusieurs).
math.randomseed os.time! * 1000 + math.floor(os.clock! * 1000) % 1000

process = ->
  facedetect.membar!          -- acquire : voir les entrées publiées par le thread principal
  path = ffi.string job.path
  img = ffi.new "Image[1]"
  img[0] = display.load_image path   -- raylib + repli conversion externe (webp/avif/jp2…)
  if img[0].width == 0 or img[0].height == 0
    job.state = 3
    return

  ori = exif.orientation path
  exif.apply rl, img, ori if ori != 1

  iw, ih = img[0].width, img[0].height

  -- Override manuel (.diapo) : visages normalisés fournis en entrée -> on saute la détection.
  local faces
  if job.override_nfaces > 0
    print "diapo: visages manuels (.diapo) pour #{path} : #{job.override_nfaces}"
    faces = {}
    for i = 1, job.override_nfaces
      b = (i - 1) * 5
      faces[i] = {
        x: job.faces[b+0] * iw, y: job.faces[b+1] * ih
        w: job.faces[b+2] * iw, h: job.faces[b+3] * ih
        score: job.faces[b+4]
      }
  else
    faces = facedetect.detect_image rl, img[0],
      detect_width: job.detect_width
      min_score: job.min_score
      rotate: job.rotate != 0

  -- Choix du visage cadré serré (un seul, au hasard) si l'option est active et >1 visage.
  focus = (job.face_focus != 0 and #faces > 1) and
    facedetect.weighted_index(faces, job.face_delta_max) or 0
  job.focus = focus

  plan = kenburns.plan iw, ih, faces,
    aspect: job.aspect
    margin: job.margin
    reverse: job.reverse != 0
    zoom_out: job.zoom_out
    zoom_max: job.zoom_max
    zoom_min: job.zoom_min
    keep_eyes: job.keep_eyes != 0
    focus: focus > 0 and focus or nil
    arc_dir: (job.arc_dir_mode == 0 and "toward") or (job.arc_dir_mode == 1 and "away") or "both"

  -- Fond flou éventuel (Image CPU ; on transmet la propriété des pixels au thread principal)
  if job.make_bg != 0
    bgimg = display.make_background_image img[0], bg_width: job.bg_width, bg_blur: job.bg_blur
    job.bg_data = bgimg.data
    job.bg_w, job.bg_h, job.bg_format = bgimg.width, bgimg.height, bgimg.format
  else
    job.bg_data = nil

  -- Visages (pour le mode debug)
  n = math.min #faces, 64
  job.nfaces = n
  for i = 1, n
    f = faces[i]
    b = (i - 1) * 5
    job.faces[b+0] = f.x
    job.faces[b+1] = f.y
    job.faces[b+2] = f.w
    job.faces[b+3] = f.h
    job.faces[b+4] = f.score or 0

  -- Plan
  s, e = plan.start, plan.finish
  job.start_x, job.start_y, job.start_w, job.start_h = s.x, s.y, s.w, s.h
  job.finish_x, job.finish_y, job.finish_w, job.finish_h = e.x, e.y, e.w, e.h
  job.arc_dx, job.arc_dy, job.arc_sign = plan.arc_dx, plan.arc_dy, plan.arc_sign

  -- Premier plan : on transmet la propriété des pixels (le thread principal libérera).
  job.img_data = img[0].data
  job.img_w, job.img_h, job.img_format = iw, ih, img[0].format

  facedetect.membar!   -- release : rend tous les résultats visibles AVANT le drapeau
  job.state = 2        -- publié en dernier

-- Boucle principale du worker. La sortie est commandée par `job.quit` (champ distinct de
-- `state`) : ainsi la publication d'un résultat (state=2) en fin de job ne peut pas écraser
-- la demande d'arrêt, ce qui bloquait le join du thread principal (image figée à la sortie).
while job.quit == 0
  if job.state == 1
    ok, err = pcall process
    unless ok
      io.stderr\write "diapo worker: #{err}\n"
      job.state = 3
  else
    ffi.C.usleep 2000   -- 2 ms en attente
