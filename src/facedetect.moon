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

-- Détection sur une Image raylib. Retourne { {x,y,w,h,score, landmarks={...}}, ... }
-- en coordonnées de l'image *d'origine*. opts.detect_width = largeur de travail (def 480),
-- opts.min_score = seuil de confiance (def 70).
detect_image = (rl, img, opts={}) ->
  detect_w  = opts.detect_width or 480
  min_score = opts.min_score or 70

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

  w, h = work[0].width, work[0].height
  src = ffi.cast "unsigned char *", work[0].data

  -- Conversion RGB -> BGR dans un buffer contigu (libfacedetection attend du BGR).
  n = w * h
  bgr = ffi.new "unsigned char[?]", n * 3
  for i = 0, n - 1
    bgr[i*3+0] = src[i*3+2]
    bgr[i*3+1] = src[i*3+1]
    bgr[i*3+2] = src[i*3+0]

  res = C.diapo_facedetect result_buffer, bgr, w, h, w * 3
  count = res[0]
  count = 0 if count < 0
  count = 1024 if count > 1024

  faces = {}
  pshort = ffi.cast "short *", ffi.cast("unsigned char *", res) + 4  -- saute l'int de tête
  inv = 1.0 / scale
  for i = 0, count - 1
    p = pshort + STRIDE * i
    score = p[0]
    continue if score < min_score
    -- coordonnées remises à l'échelle de l'image d'origine
    fx, fy, fw, fh = p[1]*inv, p[2]*inv, p[3]*inv, p[4]*inv
    lm = {}
    for k = 0, 4
      lm[#lm+1] = { x: p[5+k*2]*inv, y: p[6+k*2]*inv }
    faces[#faces+1] = { x: fx, y: fy, w: fw, h: fh, score: score, landmarks: lm }

  rl.C.UnloadImage work[0]
  faces

-- Barrière mémoire (pour la synchronisation worker <-> thread principal).
membar = -> C.diapo_membar!

{ :detect_image, :membar, :BUFFER_SIZE, :STRIDE }
