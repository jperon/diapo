-- Descripteur de visages d'une image (pur, sans FFI), pour la similarité d'ordonnancement.
CAP = 3   -- plafond d'écart de nombre de visages

-- Construit { n, cx, cy, h } depuis les visages (coord. image) ; dominant = plus grande aire.
descriptor = (faces, iw, ih) ->
  return { n: 0 } if not faces or #faces == 0
  best = faces[1]
  for f in *faces
    best = f if f.w * f.h > best.w * best.h
  { n: #faces, cx: (best.x + best.w/2)/iw, cy: (best.y + best.h/2)/ih, h: best.h/ih }

-- Distance [0,1] entre deux descripteurs.
distance = (a, b) ->
  cdiff = math.min(math.abs(a.n - b.n), CAP) / CAP
  geom = if a.n > 0 and b.n > 0
    dpos = math.sqrt((a.cx - b.cx)^2 + (a.cy - b.cy)^2) / math.sqrt(2)
    dsize = math.min math.abs(a.h - b.h), 1
    (dpos + dsize) / 2
  elseif a.n == 0 and b.n == 0
    0
  else
    1
  0.5 * cdiff + 0.5 * geom

-- Sérialisation compacte pour le cache : "n:cx:cy:h" (ou "0" si aucun visage).
encode = (d) ->
  return "0" if d.n == 0
  string.format "%d:%.4f:%.4f:%.4f", d.n, d.cx, d.cy, d.h
decode = (s) ->
  return nil unless s
  return { n: 0 } if s == "0"
  n, cx, cy, h = s\match "^(%d+):([%d.]+):([%d.]+):([%d.]+)$"
  return nil unless n
  { n: tonumber(n), cx: tonumber(cx), cy: tonumber(cy), h: tonumber(h) }

{ :descriptor, :distance, :encode, :decode, :CAP }
