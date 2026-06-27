-- Détection de visage via libfacedetection (YuNet), interfacée par FFI.
-- Expose detect_image(rl, img, opts) -> liste de visages en coordonnées image.
ffi = require "ffi"

ffi.cdef [[
  int   diapo_facedetect_buffer_size();
  int   diapo_facedetect_stride_shorts();
  int * diapo_facedetect(unsigned char *result_buffer,
                         unsigned char *image, int width, int height, int step);
  void  diapo_membar(void);
]]

lib_path = (os.getenv("DIAPO_ROOT") or ".") .. "/lib/libfacedetection.so"
C = ffi.load lib_path

BUFFER_SIZE = C.diapo_facedetect_buffer_size!
STRIDE      = C.diapo_facedetect_stride_shorts!   -- shorts par visage (16)

-- Buffer résultat réutilisé entre appels (alloué une fois).
result_buffer = ffi.new "unsigned char[?]", BUFFER_SIZE

-- Intersection sur union (IoU) de deux boîtes {x,y,w,h}.
iou = (a, b) ->
  x1 = math.max a.x, b.x
  y1 = math.max a.y, b.y
  x2 = math.min a.x + a.w, b.x + b.w
  y2 = math.min a.y + a.h, b.y + b.h
  iw, ih = x2 - x1, y2 - y1
  return 0 if iw <= 0 or ih <= 0
  inter = iw * ih
  inter / (a.w * a.h + b.w * b.h - inter)

-- Non-maximum suppression : garde, par score décroissant, les boîtes qui ne chevauchent pas
-- (IoU <= seuil) une boîte déjà retenue.
suppress_overlaps = (faces, thr=0.3) ->
  sorted = [f for f in *faces]
  table.sort sorted, (a, b) -> a.score > b.score
  kept = {}
  for f in *sorted
    overlap = false
    for k in *kept
      if iou(f, k) > thr
        overlap = true
        break
    kept[#kept + 1] = f unless overlap
  kept

-- Détection sur une Image raylib. Retourne { {x,y,w,h,score, landmarks={...}}, ... }
-- en coordonnées de l'image *d'origine*. opts.detect_width = largeur de travail (def 480),
-- opts.min_score = seuil de confiance (def 70).
detect_image = (rl, img, opts={}) ->
  detect_w  = opts.detect_width or 480
  min_score = opts.min_score or 70
  rotate    = opts.rotate                          -- force aussi la détection sur ±90°

  ow, oh = img.width, img.height
  -- Copie de travail indépendante (ImageCopy duplique les pixels) : l'image d'origine
  -- reste intacte pour l'affichage. On convertit la copie en RGB8.
  work = ffi.new "Image[1]"
  work[0] = rl.C.ImageCopy img
  rl.C.ImageFormat work, rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8

  scale = 1.0
  if ow > detect_w
    scale = detect_w / ow
    rl.C.ImageResize work, detect_w, math.floor(oh * scale + 0.5)

  w, h = work[0].width, work[0].height           -- dimensions de l'image de travail droite

  -- Détection sur une Image RGB8 `im` ; renvoie les candidats bruts (tous scores) dans
  -- les coordonnées *de cette image* : { {x,y,w,h,score, landmarks={...}}, ... }.
  run = (im) ->
    ww, wh = im.width, im.height
    s = ffi.cast "unsigned char *", im.data
    -- Conversion RGB -> BGR dans un buffer contigu (libfacedetection attend du BGR).
    nn = ww * wh
    buf = ffi.new "unsigned char[?]", nn * 3
    for i = 0, nn - 1
      buf[i*3+0] = s[i*3+2]
      buf[i*3+1] = s[i*3+1]
      buf[i*3+2] = s[i*3+0]
    res = C.diapo_facedetect result_buffer, buf, ww, wh, ww * 3
    count = res[0]
    count = 0 if count < 0
    count = 1024 if count > 1024
    ps = ffi.cast "short *", ffi.cast("unsigned char *", res) + 4  -- saute l'int de tête
    out = {}
    for i = 0, count - 1
      p = ps + STRIDE * i
      lm = [{ x: p[5+k*2], y: p[6+k*2] } for k = 0, 4]
      out[#out+1] = { x: p[1], y: p[2], w: p[3], h: p[4], score: p[0], landmarks: lm }
    out

  -- Détection dans une image pivotée de 90°, candidats reconvertis vers les coordonnées
  -- de l'image droite (`work`). rot=1 -> sens horaire (ImageRotateCW), rot=-1 -> antihoraire.
  detect_rotated = (rot) ->
    tmp = ffi.new "Image[1]"
    tmp[0] = rl.C.ImageCopy work[0]
    if rot == 1 then rl.C.ImageRotateCW tmp else rl.C.ImageRotateCCW tmp
    cands = run tmp[0]
    rl.C.UnloadImage tmp[0]
    -- Reconversion d'un point (largeur/hauteur échangées par la rotation 90°).
    pt = (x, y) -> rot == 1 and { x: y, y: h - x } or { x: w - y, y: x }
    mapped = {}
    for c in *cands
      a = pt c.x, c.y                  -- coin d'origine du rectangle pivoté
      b = pt c.x + c.w, c.y + c.h      -- coin opposé
      mapped[#mapped+1] = {
        x: math.min(a.x, b.x), y: math.min(a.y, b.y)
        w: math.abs(b.x - a.x), h: math.abs(b.y - a.y)
        score: c.score
        landmarks: [pt(p.x, p.y) for p in *c.landmarks]
      }
    mapped

  -- 1) Détection à l'endroit. 2) On tente aussi les deux rotations ±90° si `rotate` est
  -- demandé, ou si aucun visage ne passe le seuil à l'endroit (cas d'une photo tournée) ;
  -- on réunit alors tous les candidats des trois orientations.
  upright = run work[0]
  cands = upright
  if rotate or #[c for c in *upright when c.score >= min_score] == 0
    cands = [c for c in *upright]
    cands[#cands+1] = c for c in *detect_rotated 1
    cands[#cands+1] = c for c in *detect_rotated -1

  -- Remise à l'échelle (coordonnées image d'origine) d'un candidat.
  inv = 1.0 / scale
  to_orig = (c) -> {
    x: c.x*inv, y: c.y*inv, w: c.w*inv, h: c.h*inv, score: c.score
    landmarks: [{ x: p.x*inv, y: p.y*inv } for p in *c.landmarks]
  }

  -- On garde tous les visages au-dessus du seuil (pour varier le cadrage) ;
  -- à défaut, le meilleur candidat seul, pour ne pas repartir bredouille.
  faces = [to_orig c for c in *cands when c.score >= min_score]
  if #faces == 0
    best = nil
    for c in *cands
      best = c if not best or c.score > best.score
    faces = { to_orig best } if best

  -- Suppression des recouvrements (NMS) : la fusion de plusieurs orientations peut détecter
  -- plusieurs fois le même visage (un visage droit « ressort » faiblement sur les rotations).
  -- On ne garde, par score décroissant, que les boîtes ne chevauchant pas une boîte déjà
  -- retenue. Sans effet sur une seule orientation (libfacedetection déduplique déjà).
  faces = suppress_overlaps faces if #faces > 1

  rl.C.UnloadImage work[0]
  faces

-- Choisit l'index d'un visage au hasard, pondéré par son score (les visages détectés avec
-- la plus grande certitude ont plus de chance d'être sélectionnés). `delta_max` (>0) écarte
-- les visages dont le score est inférieur de plus de `delta_max` au meilleur (ex. meilleur
-- = 93, delta_max = 12 -> un visage à 80 est ignoré). Repli sur un tirage uniforme parmi
-- les éligibles si leurs scores sont tous nuls/absents.
weighted_index = (faces, delta_max) ->
  n = #faces
  return 1 if n <= 1
  best = -math.huge
  best = math.max best, (f.score or 0) for f in *faces
  thr = (delta_max and delta_max > 0) and (best - delta_max) or -math.huge
  elig = [i for i = 1, n when (faces[i].score or 0) >= thr]
  elig = [i for i = 1, n] if #elig == 0                 -- garde-fou (ne devrait pas arriver)
  total = 0
  total += math.max (faces[i].score or 0), 0 for i in *elig
  return elig[math.random #elig] if total <= 0          -- repli uniforme parmi éligibles
  r = math.random! * total
  acc = 0
  for i in *elig
    acc += math.max (faces[i].score or 0), 0
    return i if r <= acc
  elig[#elig]

-- Barrière mémoire (pour la synchronisation worker <-> thread principal).
membar = -> C.diapo_membar!

{ :detect_image, :weighted_index, :membar, :BUFFER_SIZE, :STRIDE }
