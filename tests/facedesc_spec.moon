fd = require "facedesc"

passed, failed = 0, 0
ok = (c, m) ->
  if c then passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{m}\n"

-- descriptor : dominant = plus grande aire, normalisé.
d = fd.descriptor { { x: 0, y: 0, w: 10, h: 10 }, { x: 100, y: 200, w: 100, h: 100 } }, 1000, 1000
ok d.n == 2, "n = nombre de visages"
ok math.abs(d.cx - 0.15) < 1e-9 and math.abs(d.cy - 0.25) < 1e-9, "dominant centré/normalisé"
ok math.abs(d.h - 0.1) < 1e-9, "hauteur normalisée"
ok fd.descriptor({}, 100, 100).n == 0, "aucun visage -> n=0"

-- distance : bornes, symétrie, portrait≈portrait < portrait vs paysage.
A = fd.descriptor { { x: 400, y: 100, w: 200, h: 200 } }, 1000, 1000
B = fd.descriptor { { x: 410, y: 110, w: 200, h: 200 } }, 1000, 1000   -- presque identique
C = fd.descriptor {}, 1000, 1000                                       -- paysage
ok fd.distance(A, A) == 0, "distance à soi = 0"
ok math.abs(fd.distance(A, B) - fd.distance(B, A)) < 1e-12, "symétrie"
ok fd.distance(A, B) < fd.distance(A, C), "portraits proches < portrait vs paysage"
ok fd.distance(A, C) <= 1 and fd.distance(A, C) >= 0, "distance dans [0,1]"
ok fd.distance(C, fd.descriptor({}, 10, 10)) == 0, "deux paysages -> 0"

-- encode/decode aller-retour.
e = fd.encode A
back = fd.decode e
ok back.n == A.n and math.abs(back.cx - A.cx) < 1e-3, "encode/decode aller-retour"
ok fd.decode("0").n == 0, "decode 0 -> n=0"

print "facedesc: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
