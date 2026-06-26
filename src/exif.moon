-- Lecture de l'orientation EXIF (tag 0x0112) d'un JPEG, en Lua pur (lecture d'octets).
-- Renvoie un entier 1..8 (1 = normal). Pour les non-JPEG ou sans EXIF : 1.
-- apply!(rl, img_ptr, orientation) applique la rotation/miroir à une Image raylib.

-- lit un entier non signé big/little-endian depuis une chaîne, offset 1-based
rd = (s, off, n, le) ->
  v = 0
  if le
    for i = n - 1, 0, -1
      v = v * 256 + s\byte off + i
  else
    for i = 0, n - 1
      v = v * 256 + s\byte off + i
  v

orientation = (path) ->
  f = io.open path, "rb"
  return 1 unless f
  data = f\read 65536   -- l'EXIF est dans les tout premiers octets
  f\close!
  return 1 unless data and #data > 4
  return 1 unless data\byte(1) == 0xFF and data\byte(2) == 0xD8   -- SOI JPEG

  -- parcours des segments à la recherche de APP1 (0xFFE1)
  i = 3
  app1 = nil
  while i < #data - 4
    break unless data\byte(i) == 0xFF
    marker = data\byte i + 1
    seglen = rd data, i + 2, 2, false           -- longueur big-endian
    if marker == 0xE1
      app1 = i + 4
      break
    i += 2 + seglen
  return 1 unless app1

  -- en-tête "Exif\0\0"
  return 1 unless data\sub(app1, app1 + 3) == "Exif"
  tiff = app1 + 6
  bo = data\sub tiff, tiff + 1
  le = bo == "II"                                -- little-endian si "II", sinon "MM"

  -- Les offsets EXIF sont relatifs au début du bloc TIFF. Offset de l'IFD0 :
  entry_ptr = tiff + rd data, tiff + 4, 4, le
  count = rd data, entry_ptr, 2, le
  e = entry_ptr + 2
  for _ = 1, count
    tag = rd data, e, 2, le
    if tag == 0x0112
      return rd data, e + 8, 2, le               -- valeur (type SHORT) dans le champ
    e += 12
  1

-- Applique l'orientation EXIF à une Image raylib (pointeur Image[1]).
apply = (rl, img, ori) ->
  C = rl.C
  switch ori
    when 2 then C.ImageFlipHorizontal img
    when 3
      C.ImageRotateCW img
      C.ImageRotateCW img
    when 4 then C.ImageFlipVertical img
    when 5
      C.ImageRotateCW img
      C.ImageFlipHorizontal img
    when 6 then C.ImageRotateCW img
    when 7
      C.ImageRotateCCW img
      C.ImageFlipHorizontal img
    when 8 then C.ImageRotateCCW img
  img

{ :orientation, :apply }
