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

print "kenburns: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
