-- Test du repli par rotation de la détection de visage. Nécessite raylib, testdata et
-- lib/libfacedetection.so (DIAPO_ROOT). Sauté proprement si l'un manque.
ffi = require "ffi"

passed, failed, skipped = 0, 0, false
ok = (cond, msg) ->
  if cond then passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{msg}\n"

ok_rl, rl = pcall require, "raylib"
ok_fd, fd = pcall require, "facedetect"
has_data = io.open "testdata/face.jpg", "r"
has_data\close! if has_data

if ok_rl and ok_fd and has_data
  load_img = (p) ->
    i = ffi.new "Image[1]"
    i[0] = rl.C.LoadImage p
    i

  -- À l'endroit : un visage net est trouvé.
  up = load_img "testdata/face.jpg"
  f1 = fd.detect_image rl, up[0], { min_score: 70 }
  cx, cy = up[0].width, up[0].height
  ok #f1 >= 1 and f1[1].score >= 70, "visage détecté à l'endroit"

  -- Tournée 90° (visage couché) : la détection à l'endroit échoue, le repli par rotation
  -- doit la retrouver, et la boîte reconvertie doit tomber sur le visage.
  rot = load_img "testdata/face.jpg"
  rl.C.ImageRotateCW rot
  f2 = fd.detect_image rl, rot[0], { min_score: 70 }
  ok #f2 >= 1 and f2[1].score >= 70, "visage retrouvé après rotation"
  if f2[1]
    b = f2[1]
    inside = b.x >= 0 and b.y >= 0 and b.x + b.w <= rot[0].width and b.y + b.h <= rot[0].height
    ok inside, "boîte reconvertie dans les bornes de l'image"
    -- Centre attendu : centre du visage droit transformé par la rotation CW.
    ux, uy = f1[1].x + f1[1].w/2, f1[1].y + f1[1].h/2
    ex, ey = cy - uy, ux                       -- (x,y) -> (H - y, x)
    dist = math.sqrt (b.x + b.w/2 - ex)^2 + (b.y + b.h/2 - ey)^2
    ok dist < 0.15 * math.max(rot[0].width, rot[0].height),
      "centre reconverti proche du visage attendu (écart #{math.floor dist}px)"

  -- Option rotate sur une image à l'endroit : les détections parasites des orientations
  -- pivotées doivent être fusionnées par NMS -> pas de boîtes dupliquées du même visage.
  fr = fd.detect_image rl, up[0], { min_score: 70, rotate: true }
  ok #fr == #f1, "rotate sur image droite : NMS ramène au même nombre de visages (#{#fr})"
else
  skipped = true
  io.stderr\write "  (raylib/testdata/lib indisponible : test facedetect sauté)\n"

-- Tirage pondéré par le score (pur ; ne nécessite ni image ni fenêtre).
if ok_fd
  math.randomseed 12345
  faces = { { score: 90 }, { score: 10 } }   -- ~90 % / ~10 % attendus
  counts = { 0, 0 }
  N = 4000
  for _ = 1, N
    counts[fd.weighted_index faces] += 1
  p1 = counts[1] / N
  ok p1 > 0.85 and p1 < 0.95, "pondération : visage score 90 choisi ~90 % (obtenu #{math.floor p1*100} %)"
  -- Cas dégénéré : scores nuls -> repli uniforme, pas d'erreur, index valide.
  idx = fd.weighted_index { { score: 0 }, { score: 0 } }
  ok idx == 1 or idx == 2, "scores nuls : repli uniforme, index valide"

  -- delta_max : un visage trop en-dessous du meilleur est écarté du tirage.
  trio = { { score: 93 }, { score: 80 }, { score: 50 } }
  always1 = true
  for _ = 1, 200
    always1 = false if fd.weighted_index(trio, 12) != 1   -- 80 (écart 13) et 50 écartés
    break unless always1
  ok always1, "delta_max=12 : seul le visage à 93 reste éligible"
  -- delta_max plus large : le visage à 80 redevient éligible (écart 13 <= 15).
  seen2 = false
  for _ = 1, 400
    seen2 = true if fd.weighted_index(trio, 15) == 2
    break if seen2
  ok seen2, "delta_max=15 : le visage à 80 redevient éligible"
  -- 50 (écart 43) reste écarté avec delta_max=15.
  never3 = true
  for _ = 1, 400
    never3 = false if fd.weighted_index(trio, 15) == 3
    break unless never3
  ok never3, "delta_max=15 : le visage à 50 reste écarté"

print "facedetect: #{passed} ok, #{failed} échec(s)#{skipped and ' (sauté)' or ''}"
os.exit(failed == 0 and 0 or 1)
