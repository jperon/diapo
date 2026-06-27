-- Signature visuelle d'une image : vignette couleur 8×8 (192 octets), pour mesurer la
-- ressemblance entre images. Capte la palette ET la composition grossière.
--   compute(rl, path) -> { 192 octets } (0..255) ou nil si l'image est illisible
--   distance(a, b)     -> somme des écarts absolus (L1) entre deux signatures
-- La signature reflète l'orientation EXIF (comme l'image affichée).
ffi  = require "ffi"
exif = require "exif"

SIZE = 8                 -- vignette SIZE×SIZE
LEN  = SIZE * SIZE * 3   -- 192 octets

compute = (rl, path) ->
  img = ffi.new "Image[1]"
  img[0] = rl.C.LoadImage path
  return nil if img[0].data == nil or img[0].width == 0   -- décodage échoué

  rl.C.ImageFormat img, rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8
  exif.apply rl, img, exif.orientation path                -- oriente avant de réduire
  rl.C.ImageResize img, SIZE, SIZE
  src = ffi.cast "unsigned char *", img[0].data
  sig = {}
  for i = 0, LEN - 1
    sig[i + 1] = src[i]
  rl.C.UnloadImage img[0]
  sig

-- Signature neutre (gris moyen) pour les images illisibles : elles restent dans la liste
-- sans dominer le calcul de distance.
neutral = -> [128 for _ = 1, LEN]

distance = (a, b) ->
  d = 0
  for i = 1, LEN
    diff = a[i] - b[i]
    d += diff < 0 and -diff or diff
  d

{ :compute, :distance, :neutral, :SIZE, :LEN }
