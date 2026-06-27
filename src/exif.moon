-- Lecture EXIF d'un JPEG, en Lua pur (lecture d'octets). Expose :
--   orientation(path) -> entier 1..8 (1 = normal ; 1 par défaut pour non-JPEG/sans EXIF)
--   datetime(path)    -> "YYYY:MM:DD HH:MM:SS" (DateTimeOriginal/DateTime) ou nil
--   apply(rl, img_ptr, orientation) applique la rotation/miroir à une Image raylib.

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

-- Localise le bloc TIFF de l'APP1 EXIF. Renvoie data, tiff (offset 1-based du début
-- du bloc TIFF), le (booléen little-endian) — ou nil si pas d'EXIF exploitable.
find_tiff = (path, maxread=65536) ->
  f = io.open path, "rb"
  return nil unless f
  data = f\read maxread   -- l'EXIF est dans les tout premiers octets
  f\close!
  return nil unless data and #data > 4
  return nil unless data\byte(1) == 0xFF and data\byte(2) == 0xD8   -- SOI JPEG

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
  return nil unless app1

  return nil unless data\sub(app1, app1 + 3) == "Exif"   -- en-tête "Exif\0\0"
  tiff = app1 + 6
  bo = data\sub tiff, tiff + 1
  le = bo == "II"                                -- little-endian si "II", sinon "MM"
  data, tiff, le

-- Parcourt l'IFD débutant à `ifd` (offset 1-based) et appelle fn(tag, e) pour chaque
-- entrée (e = offset 1-based de l'entrée de 12 octets). Garde-fou sur le nombre d'entrées.
each_entry = (data, ifd, le, fn) ->
  return unless ifd and ifd + 1 <= #data
  count = rd data, ifd, 2, le
  e = ifd + 2
  for _ = 1, math.min count, 1000
    break if e + 11 > #data
    fn rd(data, e, 2, le), e
    e += 12

orientation = (path) ->
  data, tiff, le = find_tiff path
  return 1 unless data
  ifd0 = tiff + rd data, tiff + 4, 4, le         -- offsets EXIF relatifs au bloc TIFF
  result = 1
  each_entry data, ifd0, le, (tag, e) ->
    result = rd data, e + 8, 2, le if tag == 0x0112   -- type SHORT, valeur dans le champ
  result

-- Date de prise de vue. Cherche DateTimeOriginal (0x9003) dans la sous-IFD EXIF
-- (pointée par 0x8769 dans l'IFD0), à défaut DateTime (0x0132) dans l'IFD0.
-- Valeur ASCII de 20 octets "YYYY:MM:DD HH:MM:SS\0", stockée à un offset (type ASCII,
-- longueur > 4). Renvoie la chaîne nettoyée (sans le \0 final) ou nil.
datetime = (path) ->
  data, tiff, le = find_tiff path
  return nil unless data
  ifd0 = tiff + rd data, tiff + 4, 4, le

  read_ascii = (e) ->
    n = rd data, e + 4, 4, le
    return nil if n < 1
    off = tiff + rd data, e + 8, 4, le           -- ASCII (>4 octets) -> offset
    s = data\sub off, off + n - 1
    s = s\gsub "%z.*$", ""                        -- coupe au premier \0
    s = s\gsub "^%s+", ""
    s = s\gsub "%s+$", ""
    #s > 0 and s or nil

  dt0132, exif_ifd = nil, nil
  each_entry data, ifd0, le, (tag, e) ->
    dt0132 = read_ascii(e) if tag == 0x0132
    exif_ifd = tiff + rd(data, e + 8, 4, le) if tag == 0x8769

  dt_orig = nil
  if exif_ifd
    each_entry data, exif_ifd, le, (tag, e) ->
      dt_orig = read_ascii(e) if tag == 0x9003
  dt_orig or dt0132

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

{ :orientation, :datetime, :apply }
