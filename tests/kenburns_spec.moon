-- Tests du cadrage Ken Burns : sélection d'un seul visage via opts.focus.
kb = require "kenburns"

passed, failed = 0, 0
ok = (cond, msg) ->
  if cond then passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{msg}\n"

-- Image 1000×1000, deux visages bien séparés (gauche et droite).
IW, IH = 1000, 1000
faceL = { x: 100, y: 450, w: 100, h: 100 }   -- centre ~ (150, 500)
faceR = { x: 800, y: 450, w: 100, h: 100 }   -- centre ~ (850, 500)
faces = { faceL, faceR }

-- Centre x de la vue serrée (finish = serré en zoom-in par défaut).
tight_cx = (opts) ->
  p = kb.plan IW, IH, faces, opts
  t = p.finish
  t.x + t.w / 2

cxL = tight_cx { aspect: 1.0, focus: 1 }
cxR = tight_cx { aspect: 1.0, focus: 2 }
cxAll = tight_cx { aspect: 1.0 }

ok cxL < IW/2, "focus=1 : vue serrée à gauche (cx=#{math.floor cxL})"
ok cxR > IW/2, "focus=2 : vue serrée à droite (cx=#{math.floor cxR})"
ok cxL < cxR, "focus=1 plus à gauche que focus=2"
-- Sans focus : englobe les deux -> centre proche du milieu, entre les deux serrés.
ok math.abs(cxAll - IW/2) < math.abs(cxL - IW/2), "sans focus : cadrage plus central que focus=1"
ok cxAll > cxL and cxAll < cxR, "sans focus : centre entre les deux visages"

-- focus hors limites ou image à un seul visage : comportement « tous » (pas d'erreur).
one = { faceL }
p1a = kb.plan IW, IH, one, { aspect: 1.0 }
p1b = kb.plan IW, IH, one, { aspect: 1.0, focus: 1 }
ok math.abs((p1a.finish.x + p1a.finish.w/2) - (p1b.finish.x + p1b.finish.w/2)) < 1e-6,
  "un seul visage : focus sans effet"
ok (kb.plan IW, IH, faces, { aspect: 1.0, focus: 99 }) != nil, "focus hors limites : pas d'erreur"

-- ── Arc bi-axe ────────────────────────────────────────────────────────────────
-- Composantes proportionnelles à l'écart au centre, sens forcé via arc_sign.
-- Sujet en haut-gauche (centre 250,250 dans une image 1000×1000) -> dx<0, dy<0.
bboxTL = { x: 200, y: 200, w: 100, h: 100 }
dx, dy, sgn = kb.arc_components bboxTL, 1000, 1000, "toward", 1
ok dx < 0 and dy < 0, "toward : bosse vers le sujet en haut-gauche (dx,dy<0)"
ok sgn == 1, "sens forcé conservé"
dxA, dyA = kb.arc_components bboxTL, 1000, 1000, "away", -1
ok dxA > 0 and dyA > 0, "away : bosse à l'opposé du sujet (dx,dy>0)"
ok math.abs(dxA + dx) < 1e-9 and math.abs(dyA + dy) < 1e-9, "away = -toward (composantes opposées)"

-- Sujet centré -> aucune bosse.
dxc, dyc = kb.arc_components { x: 450, y: 450, w: 100, h: 100 }, 1000, 1000, "both", 1
ok math.abs(dxc) < 1e-9 and math.abs(dyc) < 1e-9, "sujet centré : bosse nulle"
-- Pas de sujet (bbox nil) -> neutre.
dxn, dyn = kb.arc_components nil, 1000, 1000, "both"
ok dxn == 0 and dyn == 0, "pas de sujet : bosse nulle"

-- `at` applique la bosse sur les deux axes au milieu du mouvement (e=0.5, sin=1).
kbArc = { start: { x: 0, y: 0, w: 1000, h: 1000 }, finish: { x: 0, y: 0, w: 1000, h: 1000 },
          img_w: 1000, img_h: 1000, free_x: true, free_y: true, arc_dx: -0.5, arc_dy: 0.25 }
mid = kb.at kbArc, 0.5, 0.1
ok math.abs(mid.x - (0.1 * -0.5 * 1000)) < 1e-6, "at : déviation x = arc·arc_dx·w au milieu"
ok math.abs(mid.y - (0.1 * 0.25 * 1000)) < 1e-6, "at : déviation y = arc·arc_dy·h au milieu"
ends = kb.at kbArc, 0.0, 0.1
ok math.abs(ends.x) < 1e-6 and math.abs(ends.y) < 1e-6, "at : bosse nulle aux extrémités"
-- arc=0 -> aucune déviation même avec des composantes.
flat = kb.at kbArc, 0.5, 0
ok math.abs(flat.x) < 1e-6 and math.abs(flat.y) < 1e-6, "at : arc=0 -> pas de déviation"

-- arc_sign mémorisé : repasser le sens reproduit exactement les mêmes composantes.
p1 = kb.plan IW, IH, { faceL }, { aspect: 1.0, arc_dir: "both" }
p2 = kb.plan IW, IH, { faceL }, { aspect: 1.0, arc_dir: "both", arc_sign: p1.arc_sign }
ok math.abs(p1.arc_dx - p2.arc_dx) < 1e-9 and math.abs(p1.arc_dy - p2.arc_dy) < 1e-9,
  "arc_sign mémorisé : composantes reproduites au recalcul"

-- ── Harmonisation des transitions ───────────────────────────────────────────────────────
-- view_for_placement : le visage atterrit bien au placement demandé.
do
  face = { cx: 300, cy: 200, h: 80 }
  P = { sx: 0.5, sy: 0.4, hs: 0.25 }
  v = kb.view_for_placement face, P, 16/9
  ok math.abs(face.h / v.h - 0.25) < 1e-9, "view_for_placement : taille écran = hs"
  ok math.abs((face.cx - v.x)/v.w - 0.5) < 1e-9, "view_for_placement : sx respecté"
  ok math.abs((face.cy - v.y)/v.h - 0.4) < 1e-9, "view_for_placement : sy respecté"

-- joint_placement : deux visages compatibles -> placement commun, coïncidence écran.
do
  mk = (cx) -> {
    face: { :cx, cy: 500, h: 100 }, full_h: 1000, zmin: 0.8, zmax: 3.0
    img_w: 1000, img_h: 1000, free_x: false, free_y: false
    nat_view: { x: 0, y: 0, w: 1000, h: 1000 }
  }
  A, B = mk(400), mk(600)
  vA, vB, okj = kb.joint_placement A, B, 1.0, 0.3, 0.3
  ok okj, "joint_placement : réussit pour deux visages compatibles"
  if okj
    ok math.abs(A.face.h/vA.h - B.face.h/vB.h) < 1e-9, "joint : visages de même taille écran"
    sxA = (A.face.cx - vA.x)/vA.w
    sxB = (B.face.cx - vB.x)/vB.w
    ok math.abs(sxA - sxB) < 1e-9, "joint : visages à la même position écran"

-- joint_placement : tailles inconciliables (zoom figé) hors tolérance -> renoncement.
do
  base = (h) -> {
    face: { cx: 500, cy: 500, :h }, full_h: 1000, zmin: 1.0, zmax: 1.0
    img_w: 1000, img_h: 1000, free_x: false, free_y: false
    nat_view: { x: 0, y: 0, w: 1000, h: 1000 }
  }
  _, _, okj = kb.joint_placement base(20), base(400), 1.0, 0.1, 0.3
  ok not okj, "joint_placement : renonce si tailles inconciliables (hors tolérance)"

-- Coût : une rencontre de natures concordantes (deux vues serrées) coûte moins qu'une
-- rencontre serré↔large. C'est la base du choix de direction quand alternate est désactivé.
do
  mkside = (nat_h) -> {
    face: { cx: 500, cy: 500, h: 100 }, full_h: 1000, zmin: 0.8, zmax: 6.0
    img_w: 1000, img_h: 1000, free_x: false, free_y: false
    nat_view: { x: 0, y: 0, w: nat_h, h: nat_h }
  }
  A = mkside 200                                   -- A finit serré (petite vue -> grand visage)
  _, _, _, cost_match = kb.joint_placement A, mkside(200), 1.0, 0.5, 0.5   -- B démarre serré
  _, _, _, cost_diff  = kb.joint_placement A, mkside(900), 1.0, 0.5, 0.5   -- B démarre large
  ok cost_match < cost_diff, "coût : natures concordantes (serré↔serré) < discordantes"

print "kenburns: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
