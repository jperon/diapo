-- Calcul du mouvement Ken Burns guidé par les visages.
-- Produit deux rectangles "source" (début/fin) au ratio de l'écran, en coordonnées image,
-- puis interpole entre eux avec un easing.

-- Rectangle de ratio `aspect` centré sur (cx,cy), de demi-dimensions dérivées d'une taille.
-- On part d'une largeur cible `w` et on ajuste la hauteur, ou l'inverse, pour coller au ratio.
fit_aspect = (w, h, aspect) ->
  if w / h > aspect
    h = w / aspect   -- trop large -> on augmente la hauteur
  else
    w = h * aspect   -- trop haut -> on augmente la largeur
  w, h

-- Ramène un rect (x,y,w,h) à l'intérieur de [0,img_w]x[0,img_h].
-- Si trop grand, on le réduit (en gardant le ratio) jusqu'à tenir.
clamp_rect = (r, img_w, img_h) ->
  -- réduction si plus grand que l'image
  if r.w > img_w
    s = img_w / r.w
    r.w *= s
    r.h *= s
  if r.h > img_h
    s = img_h / r.h
    r.w *= s
    r.h *= s
  -- recentrage dans les bornes
  r.x = math.max 0, math.min r.x, img_w - r.w
  r.y = math.max 0, math.min r.y, img_h - r.h
  r

-- Rectangle "plein cadre" : plus grand rect au ratio écran tenant dans l'image, centré.
full_rect = (img_w, img_h, aspect) ->
  w, h = img_w, img_h
  if img_w / img_h > aspect
    w = img_h * aspect
  else
    h = img_w / aspect
  { x: (img_w - w)/2, y: (img_h - h)/2, :w, :h }

-- Boîte englobante des visages (coordonnées image), ou nil si aucun.
faces_bbox = (faces) ->
  return nil if #faces == 0
  x0, y0 = math.huge, math.huge
  x1, y1 = -math.huge, -math.huge
  for f in *faces
    x0 = math.min x0, f.x
    y0 = math.min y0, f.y
    x1 = math.max x1, f.x + f.w
    y1 = math.max y1, f.y + f.h
  { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }

-- Étend `r` (au ratio `aspect`) pour contenir tous les points `pts` ({x,y}), en gardant
-- le ratio. Peut faire déborder `r` hors image (le clamp éventuel est à la charge de l'appelant).
expand_to_contain = (r, pts, aspect) ->
  x0, y0 = r.x, r.y
  x1, y1 = r.x + r.w, r.y + r.h
  for p in *pts
    x0 = math.min x0, p.x
    y0 = math.min y0, p.y
    x1 = math.max x1, p.x
    y1 = math.max y1, p.y
  w = x1 - x0
  h = y1 - y0
  cx = (x0 + x1) / 2
  cy = (y0 + y1) / 2
  w, h = fit_aspect w, h, aspect      -- réagrandit la dimension déficiente autour du centre
  { x: cx - w/2, y: cy - h/2, :w, :h }

-- Points des yeux de tous les visages (landmarks YuNet : 1 = œil droit, 2 = œil gauche).
eye_points = (faces) ->
  pts = {}
  for f in *faces
    if f.landmarks and f.landmarks[1] and f.landmarks[2]
      pts[#pts+1] = f.landmarks[1]
      pts[#pts+1] = f.landmarks[2]
  pts

-- Composantes de la bosse d'arc : un vecteur (dx,dy) proportionnel à l'écart du sujet au
-- centre de l'image (normalisé par la demi-dimension, borné à [-1,1]), affecté d'un signe
-- tiré au hasard parmi les sens activés. +1 = bosse VERS le sujet ; -1 = à l'opposé.
--   bbox      boîte du sous-ensemble cadré (nil = pas de sujet -> arc neutre)
--   dir       "toward" | "away" | "both" (sens tirables)
--   sign_in   sens forcé (optionnel) : reproduit un arc mémorisé (recalcul/resize)
-- Renvoie dx, dy, sign (sign mémorisable pour un recalcul ultérieur).
arc_components = (bbox, img_w, img_h, dir, sign_in) ->
  return 0, 0, 1 unless bbox
  cx = bbox.x + bbox.w/2
  cy = bbox.y + bbox.h/2
  clamp = (v) -> math.max -1, math.min v, 1
  dx = clamp (cx - img_w/2) / (img_w/2)
  dy = clamp (cy - img_h/2) / (img_h/2)
  sign = sign_in
  unless sign
    sign = switch dir
      when "toward" then 1
      when "away"   then -1
      else math.random! < 0.5 and -1 or 1   -- "both" (défaut)
  sign * dx, sign * dy, sign

-- Construit le plan Ken Burns.
--   opts.aspect    ratio écran
--   opts.margin    marge autour des visages pour le cadrage serré (def 0.35)
--   opts.reverse   alterne le sens (zoom-in <-> zoom-out)
--   opts.zoom_out  >1 autorise un point de vue plus large que l'image (fond flou autour)
--   opts.keep_eyes garantit que les yeux restent dans la vue tout au long du mouvement
--   opts.focus     index (1-based) du seul visage à cadrer serré (sinon : tous). La vue
--                  large reste l'image entière (tout le monde visible au départ).
--   opts.arc_dir   sens tirables de la bosse d'arc : "toward" | "away" | "both" (def)
--   opts.arc_sign  sens forcé (optionnel) pour reproduire un arc mémorisé
plan = (img_w, img_h, faces, opts={}) ->
  aspect   = opts.aspect or (16/9)
  margin   = opts.margin or 0.35
  zoom_out = opts.zoom_out or 1.0

  -- Sous-ensemble cadré serré : un seul visage si `focus` désigne un visage existant,
  -- sinon tous. (Sans effet s'il n'y a qu'un visage.)
  sel = (opts.focus and faces[opts.focus]) and { faces[opts.focus] } or faces

  wide = full_rect img_w, img_h, aspect
  bbox = faces_bbox sel

  -- Point de vue large : éventuellement plus grand que l'image (dézoom + fond flou).
  -- Centré sur le centre de l'image ; non clampé aux bornes si zoom_out > 1.
  -- On plafonne le dézoom pour qu'UNE SEULE dimension dépasse l'image (l'autre reste
  -- pleine) : au-delà, du fond flou apparaîtrait sur les quatre côtés. La dimension déjà
  -- la plus serrée (celle qui touche le bord image dans `full_rect`) est celle qui déborde.
  wide_view = wide
  if zoom_out > 1.0
    r = (img_w / img_h) / aspect
    cap = math.max r, 1 / r           -- dézoom max gardant une dimension pleine
    z = math.min zoom_out, cap
    w = wide.w * z
    h = wide.h * z
    wide_view = { x: img_w/2 - w/2, y: img_h/2 - h/2, :w, :h }

  local tight
  if bbox
    cx = bbox.x + bbox.w/2
    cy = bbox.y + bbox.h/2
    -- largeur minimale d'un rect au ratio écran contenant TOUTE la bbox
    w_min = math.max bbox.w, bbox.h * aspect
    -- on ajoute la marge, sans dépasser le plein cadre ni descendre sous w_min
    w = math.min wide.w, math.max w_min, w_min * (1 + margin)
    h = w / aspect
    tight = clamp_rect { x: cx - w/2, y: cy - h/2, :w, :h }, img_w, img_h
  else
    -- pas de visage : léger zoom centré + dérive douce
    w = wide.w / 1.25
    h = wide.h / 1.25
    cx = wide.x + wide.w/2 + wide.w*0.08
    cy = wide.y + wide.h/2 - wide.h*0.05
    tight = clamp_rect { x: cx - w/2, y: cy - h/2, :w, :h }, img_w, img_h

  -- Bornes de zoom explicites. Le zoom est exprimé en magnification relative à la vue
  -- plein-cadre (full_rect) : >1 = plus serré, <1 = plus large (dézoom).
  --   zoom effectif max = min(zoom_max, zoom_max_calculé sur les visages)   -- vue serrée
  --   zoom effectif min = max(zoom_min, zoom_min_calculé via zoom_out)      -- vue large
  -- (zoom_max<=0 = pas de limite haute ; zoom_min absent = pas de plancher.)
  recenter_zoom = (cx, cy, zoom) ->
    w = wide.w / zoom
    h = wide.h / zoom
    { x: cx - w/2, y: cy - h/2, :w, :h }

  zmax_opt = (opts.zoom_max and opts.zoom_max > 0) and opts.zoom_max or math.huge
  zmin_opt = opts.zoom_min or 0
  calc_zmax = wide.w / tight.w
  calc_zmin = wide.w / wide_view.w
  zmax_eff = math.min zmax_opt, calc_zmax
  zmin_eff = math.max zmin_opt, calc_zmin
  zmin_eff = math.min zmin_eff, zmax_eff          -- cohérence min <= max

  tight = recenter_zoom (tight.x + tight.w/2), (tight.y + tight.h/2), zmax_eff
  tight = clamp_rect(tight, img_w, img_h) if tight.w <= img_w and tight.h <= img_h
  wide_view = recenter_zoom img_w/2, img_h/2, zmin_eff

  -- Option : garder les yeux dans la vue. On étend chaque extrémité pour contenir les
  -- points des yeux. La vue serrée est ensuite reclampée dans l'image ; la vue large
  -- (potentiellement hors image en mode zoom_out) ne l'est pas.
  if opts.keep_eyes
    eyes = eye_points sel
    if #eyes > 0
      tight = clamp_rect (expand_to_contain tight, eyes, aspect), img_w, img_h
      wide_view = expand_to_contain wide_view, eyes, aspect
      -- on ne reclampe la vue large dans l'image que si elle y tient (sinon : dézoom)
      if wide_view.w <= img_w and wide_view.h <= img_h
        wide_view = clamp_rect wide_view, img_w, img_h

  -- Par défaut on termine serré sur les visages (zoom-in) ; reverse = zoom-out.
  start_r, end_r = wide_view, tight
  start_r, end_r = tight, wide_view if opts.reverse

  -- Axes "libres" : ceux où une extrémité déborde l'image (donc fond visible). Sur ces
  -- axes on n'écrête PAS pendant l'interpolation, sinon un bord se "colle" au bord de
  -- l'écran et casse la trajectoire (effet zig-zag). L'interpolation linéaire est lisse
  -- par construction ; sur les axes non libres, les deux extrémités sont dans l'image,
  -- donc l'interpolation y reste sans avoir besoin d'écrêtage.
  free_x = start_r.w > img_w + 0.5 or end_r.w > img_w + 0.5
  free_y = start_r.h > img_h + 0.5 or end_r.h > img_h + 0.5

  -- Bosse d'arc bi-axe : composantes dérivées de la position du sujet (bbox du cadrage
  -- serré). Le sens est tiré (ou repris via opts.arc_sign pour rester stable au recalcul).
  arc_dx, arc_dy, arc_sign = arc_components bbox, img_w, img_h, (opts.arc_dir or "both"), opts.arc_sign

  -- Données d'harmonisation des transitions (cf. joint_placement) : le visage de référence
  -- (bbox du sous-ensemble cadré) en coord. image, les bornes de zoom effectives et la
  -- hauteur plein-cadre. `harm` nil = pas de visage -> pas d'harmonisation (repli centré).
  harm = bbox and { cx: bbox.x + bbox.w/2, cy: bbox.y + bbox.h/2, w: bbox.w, h: bbox.h } or nil

  -- Centroïde des yeux du sous-ensemble cadré (coord. image), pour le repli d'alignement léger
  -- des yeux quand l'harmonisation complète renonce. nil si aucun landmark d'yeux disponible.
  eyes_c = nil
  eyes_pts = eye_points sel
  if #eyes_pts > 0
    ex, ey = 0, 0
    for p in *eyes_pts
      ex += p.x
      ey += p.y
    eyes_c = { x: ex / #eyes_pts, y: ey / #eyes_pts }

  { start: start_r, finish: end_r, :aspect, :img_w, :img_h, :free_x, :free_y,
    :arc_dx, :arc_dy, :arc_sign, :harm, :eyes_c, full_h: wide.h, zmin: zmin_eff, zmax: zmax_eff }

-- ── Harmonisation des transitions ──────────────────────────────────────────────────────
-- Un "placement" P = {sx, sy, hs} décrit où apparaît un visage à l'écran (sx,sy ∈ [0,1]) et
-- sa taille (hs = fraction de la hauteur écran). Deux images dont les visages sont au MÊME
-- placement voient leurs visages coïncider pendant le fondu.

-- Vue (rect au ratio `aspect`) plaçant le visage {cx,cy,h} au placement P.
view_for_placement = (face, P, aspect) ->
  vh = face.h / P.hs
  vw = vh * aspect
  { x: face.cx - P.sx * vw, y: face.cy - P.sy * vh, w: vw, h: vh }

-- Plage de hs réalisable (du zoom) : hs petit = vue large, hs grand = vue serrée.
hs_range = (face, full_h, zmin, zmax) ->
  base = face.h / full_h
  base * zmin, base * zmax

-- Plages de position (sx,sy) gardant la vue dans l'image, à hs fixé. Sur un axe "libre"
-- (fond flou autorisé), pas de borne -> [0,1].
pos_range = (face, hs, aspect, img_w, img_h, free_x, free_y) ->
  vh = face.h / hs
  vw = vh * aspect
  sxl, sxh = 0, 1
  unless free_x
    sxl = math.max 0, (face.cx + vw - img_w) / vw
    sxh = math.min 1, face.cx / vw
  syl, syh = 0, 1
  unless free_y
    syl = math.max 0, (face.cy + vh - img_h) / vh
    syh = math.min 1, face.cy / vh
  sxl, sxh, syl, syh

-- Choisit une valeur dans l'intersection [alo,ahi]∩[blo,bhi] la plus proche de `target` ; si
-- l'intersection est vide, renvoie le milieu et l'écart (résidu) entre les deux plages.
overlap_pick = (alo, ahi, blo, bhi, target) ->
  lo = math.max alo, blo
  hi = math.min ahi, bhi
  if lo <= hi
    (math.max lo, math.min target, hi), 0
  else
    (lo + hi) / 2, lo - hi

-- Placement conjoint de deux côtés A (sortante) et B (entrante), chacun :
--   { face={cx,cy,h}, full_h, zmin, zmax, img_w, img_h, free_x, free_y, nat_view }
-- nat_view = vue naturelle de rencontre (cible de taille hs0 = face.h/nat_view.h). Priorité :
-- coïncidence (même P), puis position proche du centre, le tout dans les tolérances.
-- Renvoie viewA, viewB, ok, cost — cost (plus petit = meilleur, math.huge si on renonce) mesure
-- le compromis (résidu de position + écart de zoom + décentrage), pour comparer des variantes.
joint_placement = (A, B, aspect, zoom_tol=0.25, pos_tol=0.15) ->
  hsA0 = A.face.h / A.nat_view.h
  hsB0 = B.face.h / B.nat_view.h
  aMin, aMax = hs_range A.face, A.full_h, A.zmin, A.zmax
  bMin, bMax = hs_range B.face, B.full_h, B.zmin, B.zmax
  lo = math.max aMin, bMin
  hi = math.min aMax, bMax
  target = math.sqrt hsA0 * hsB0          -- moyenne géométrique des tailles naturelles
  local hs
  if lo <= hi
    hs = math.max lo, math.min target, hi
  else
    mid = (lo + hi) / 2
    return nil, nil, false, math.huge if (lo - hi) / mid > zoom_tol   -- écart de zoom trop grand
    hs = mid
  -- Plancher "couverture écran" : la vue ne doit jamais flotter (les deux dimensions de l'image
  -- plus petites que l'écran). vh<=img_h <=> hs>=face.h/img_h ; vw<=img_w <=> hs>=face.h*aspect/
  -- img_w. On garantit le plus facile des deux (min) en remontant hs si besoin (zoom-in).
  fill = (s) -> math.min s.face.h / s.img_h, s.face.h * aspect / s.img_w
  hs = math.max hs, (fill A), (fill B)
  -- Cible de position = moyenne des positions écran NATURELLES du visage (on respecte ainsi un
  -- cadrage haut/bas commun au lieu de tout ramener au centre).
  nat_sx = (s) -> (s.face.cx - s.nat_view.x) / s.nat_view.w
  nat_sy = (s) -> (s.face.cy - s.nat_view.y) / s.nat_view.h
  tx = math.max 0, math.min 1, ((nat_sx A) + (nat_sx B)) / 2
  ty = math.max 0, math.min 1, ((nat_sy A) + (nat_sy B)) / 2
  axl, axh, ayl, ayh = pos_range A.face, hs, aspect, A.img_w, A.img_h, A.free_x, A.free_y
  bxl, bxh, byl, byh = pos_range B.face, hs, aspect, B.img_w, B.img_h, B.free_x, B.free_y
  sx, rx = overlap_pick axl, axh, bxl, bxh, tx
  sy, ry = overlap_pick ayl, ayh, byl, byh, ty
  return nil, nil, false, math.huge if rx > pos_tol or ry > pos_tol   -- positions inconciliables
  P = { :sx, :sy, :hs }
  -- Coût = compromis : à quel point chaque vue est tirée de SA taille naturelle (hsA0/hsB0) et
  -- de sa position naturelle, plus le résidu d'intersection.
  cost = rx + ry + math.abs(math.log(hs / hsA0)) + math.abs(math.log(hs / hsB0)) +
    0.3 * (math.abs(sx - tx) + math.abs(sy - ty))
  (view_for_placement A.face, P, aspect), (view_for_placement B.face, P, aspect), true, cost

-- Phase brute [0,1] à partir du temps écoulé et de la durée du mouvement.
-- bounce=true : effet "rebond" (aller-retour) si l'affichage dure plus que le mouvement.
phase = (elapsed, motion_dur, bounce) ->
  return math.max 0, math.min(elapsed / motion_dur, 1) unless bounce
  x = elapsed / motion_dur
  p = x % 2
  p < 1 and p or 2 - p

-- Easing accélération/décélération paramétrable. power=1 linéaire ; 2 ≈ doux ; >2 marqué.
ease = (t, power=2) ->
  t = math.max 0, math.min t, 1
  return t if power <= 1
  if t < 0.5
    0.5 * (2 * t) ^ power
  else
    1 - 0.5 * (2 - 2 * t) ^ power

-- Plafond d'amplitude d'arc garantissant un mouvement MONOTONE sur un axe : la bosse ne doit
-- jamais inverser le sens de la translation linéaire (sinon le sujet part puis revient = zig-zag).
-- Position : p(e) = p0 + L·e + A·d·W(e)·sin(πe), avec L = p1-p0 le déplacement linéaire et
-- W(e) = w0+(w1-w0)·e la taille interpolée. Vitesse : p'(e) = L + A·m(e), où
-- m(e) = d·((w1-w0)·sin(πe) + W(e)·π·cos(πe)). On impose A·max|m| ≤ 0.9·|L| → p'(e) garde le
-- signe de L partout. Quand L≈0 (translation nette quasi nulle), le plafond force A→0.
arc_axis_cap = (L, w0, w1, d) ->
  return math.huge if d == 0
  mmax = 0
  for k = 0, 16
    e = k / 16
    W = w0 + (w1 - w0) * e
    m = math.abs d * ((w1 - w0) * math.sin(math.pi * e) + W * math.pi * math.cos(math.pi * e))
    am = math.abs m
    mmax = am if am > mmax
  return math.huge if mmax == 0
  0.9 * math.abs(L) / mmax

-- Rectangle interpolé pour une progression `e` déjà lissée (in [0,1]).
-- `arc` ajoute une bosse bi-axe (nulle aux extrémités, maximale au milieu) : le cadrage
-- dévie selon un vecteur (kb.arc_dx, kb.arc_dy) dérivé de la position du sujet, puis revient
-- à son cadrage final. `arc` est l'amplitude scalaire (cfg.face_arc) ; les composantes
-- portent la direction et le signe (sens tiré au calcul du plan). L'amplitude est plafonnée
-- par axe (arc_axis_cap) pour que la trajectoire reste monotone — garde-fou anti-zig-zag.
at = (kb, e, arc=0) ->
  e = math.max 0, math.min e, 1
  a, b = kb.start, kb.finish
  r =
    x: a.x + (b.x - a.x) * e
    y: a.y + (b.y - a.y) * e
    w: a.w + (b.w - a.w) * e
    h: a.h + (b.h - a.h) * e
  if arc != 0
    bump = math.sin math.pi * e
    dx, dy = (kb.arc_dx or 0), (kb.arc_dy or 0)
    ax = math.min arc, arc_axis_cap (b.x - a.x), a.w, b.w, dx
    ay = math.min arc, arc_axis_cap (b.y - a.y), a.h, b.h, dy
    r.x += ax * dx * r.w * bump
    r.y += ay * dy * r.h * bump
  -- Écrêtage UNIQUEMENT sur les axes non libres (où aucun fond n'est censé apparaître) :
  -- y borne l'effet d'`arc` ; x est un no-op (interpolation déjà interne). Sur les axes
  -- libres on ne touche à rien -> trajectoire lisse, pas de zig-zag.
  unless kb.free_y
    r.y = math.max 0, math.min r.y, kb.img_h - r.h if r.h <= kb.img_h
  unless kb.free_x
    r.x = math.max 0, math.min r.x, kb.img_w - r.w if r.w <= kb.img_w
  r

{ :plan, :at, :phase, :ease, :full_rect, :faces_bbox, :fit_aspect, :clamp_rect,
  :expand_to_contain, :eye_points, :arc_components,
  :view_for_placement, :hs_range, :pos_range, :joint_placement }
