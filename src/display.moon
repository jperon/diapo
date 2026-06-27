-- Couche d'affichage raylib : fenêtre, chargement de textures, rendu d'une vue Ken Burns,
-- et fondu (crossfade) entre deux diapositives.
ffi = require "ffi"
rl  = require "raylib"
C   = rl.C

-- Sommeil réel (le compositeur Wayland ne bloquant pas le CPU sur le vsync, on cadence la
-- boucle nous-mêmes ; C.WaitTime de raylib fait un busy-wait qui sature un cœur).
ffi.cdef "struct timespec { long tv_sec; long tv_nsec; }; int nanosleep(const struct timespec *req, struct timespec *rem);"
sleep_ts = ffi.new "struct timespec[1]"
sleep = (s) ->
  return if s <= 0
  sleep_ts[0].tv_sec = math.floor s
  sleep_ts[0].tv_nsec = math.floor (s - math.floor s) * 1e9
  ffi.C.nanosleep sleep_ts, nil

WHITE = rl.Color 255, 255, 255, 255
BLACK = rl.Color 0, 0, 0, 255

state = { w: 0, h: 0 }

-- Détection de la rotation d'écran via SDL. raylib (backend SDL) ne redimensionne PAS sa
-- surface plein écran quand l'écran pivote sous Wayland : GetScreenWidth/Height, le moniteur
-- ET le render restent à leur valeur d'origine (vérifié par instrumentation) — diapo n'est donc
-- notifié par aucune grandeur raylib. On interroge directement SDL (chargé en NEEDED par
-- raylib, ses symboles sont résolus par le namespace `C`) : SDL_GetDisplayOrientation change,
-- lui, à la rotation. SDL_DisplayOrientation : 0=UNKNOWN 1/2=LANDSCAPE 3/4=PORTRAIT.
-- SDL_DisplayOrientation : 0=UNKNOWN, 1=LANDSCAPE, 2=LANDSCAPE_FLIPPED, 3=PORTRAIT,
-- 4=PORTRAIT_FLIPPED. SDL est chargé en NEEDED par raylib -> ses symboles sont résolus par `C`.
ffi.cdef "int SDL_GetDisplayOrientation(int displayIndex);"
orientation = ->
  ok, o = pcall -> C.SDL_GetDisplayOrientation C.GetCurrentMonitor!
  ok and o or 0

-- Sous Wayland, lors d'une rotation d'écran, raylib/SDL NE redimensionnent PAS la surface plein
-- écran : GetScreenWidth/Height (le framebuffer) restent en paysage (vérifié par instrumentation)
-- et le compositeur étire ce framebuffer paysage sur l'affichage devenu portrait -> image écrasée.
-- On corrige côté rendu : on raisonne sur un « canevas logique » à l'aspect réellement affiché
-- (dimensions échangées en portrait), puis on mappe vers le framebuffer de façon anisotrope ; le
-- compositeur applique la transformation inverse, restituant les bonnes proportions.
--   state.fw/fh : framebuffer réel (ce que dessine le GPU)   state.w/h : canevas logique.
refresh_size = ->
  o = orientation!
  fw, fh = C.GetScreenWidth!, C.GetScreenHeight!
  if fw > 0 and fh > 0
    state.fw, state.fh = fw, fh
    portrait = (o == 3 or o == 4)
    if portrait
      state.w, state.h = fh, fw     -- aspect affiché = portrait
    else
      state.w, state.h = fw, fh
  state

-- Convertit un rectangle exprimé en coordonnées du canevas logique vers le framebuffer réel
-- (mise à l'échelle anisotrope que le compositeur inversera).
to_fb = (x, y, w, h) ->
  sx = state.fw / state.w
  sy = state.fh / state.h
  x * sx, y * sy, w * sx, h * sy

-- Ouvre la fenêtre. opts.fullscreen (def true), opts.title, opts.fps (def 60),
-- opts.width/opts.height (taille de la fenêtre en mode fenêtré).
init = (opts={}) ->
  windowed = opts.fullscreen == false
  state.win_w = opts.width or 1280       -- taille mémorisée pour le retour en fenêtré (touche F)
  state.win_h = opts.height or 720
  -- Toujours redimensionnable : permet de basculer plein écran <-> fenêtré à la volée.
  -- FLAG_VSYNC_HINT : avec le backend SDL, le vsync Wayland bloque proprement (la frame dort,
  -- ~5 % CPU). La cadence nanosleep du slideshow plafonne en plus à cfg.fps si < rafraîchissement.
  flags = rl.FLAG_VSYNC_HINT + rl.FLAG_WINDOW_RESIZABLE
  C.SetConfigFlags flags
  C.InitWindow state.win_w, state.win_h, opts.title or "diapo"
  unless windowed
    -- En plein écran : on prend la résolution du moniteur courant.
    mon = C.GetCurrentMonitor!
    mw, mh = C.GetMonitorWidth(mon), C.GetMonitorHeight(mon)
    C.SetWindowSize mw, mh if mw > 0 and mh > 0
    C.ToggleFullscreen!
  C.SetTargetFPS opts.fps or 60
  C.SetExitKey rl.KEY_ESCAPE
  -- Laisse le compositeur appliquer le plein écran / l'orientation avant de lire la taille
  -- réelle de la surface (sinon on récupère la taille d'InitWindow, paysage par défaut).
  for _ = 1, 4
    C.BeginDrawing!
    C.ClearBackground BLACK
    C.EndDrawing!
  refresh_size!
  state

-- Bascule plein écran <-> fenêtré. Le changement de taille de surface qui en résulte est
-- détecté par la boucle (refresh_size) qui réadapte les plans Ken Burns au nouveau ratio.
toggle_fullscreen = ->
  if C.IsWindowFullscreen!
    C.ToggleFullscreen!
    C.SetWindowSize state.win_w, state.win_h
  else
    mon = C.GetCurrentMonitor!
    mw, mh = C.GetMonitorWidth(mon), C.GetMonitorHeight(mon)
    C.SetWindowSize mw, mh if mw > 0 and mh > 0
    C.ToggleFullscreen!

close = -> C.CloseWindow!
should_close = -> C.WindowShouldClose!
screen = -> state.w, state.h
aspect = -> state.w / state.h

-- Image (CPU) -> Texture (GPU), avec filtrage bilinéaire pour un zoom lisse.
load_texture = (img) ->
  tex = C.LoadTextureFromImage img
  C.SetTextureFilter tex, rl.TEXTURE_FILTER_BILINEAR
  tex
unload_texture = (tex) -> C.UnloadTexture tex

-- Crée (côté CPU) une image de fond floutée à partir de `img`. Réduite puis floutée
-- (flou gaussien) : bon marché et exploitable hors thread GL. L'appelant en fait une
-- texture via load_texture et libère l'Image.
make_background_image = (img, opts={}) ->
  bg = ffi.new "Image[1]"
  bg[0] = C.ImageCopy img
  target = opts.bg_width or 320
  if img.width > target
    h = math.floor img.height * target / img.width + 0.5
    C.ImageResize bg, target, math.max 1, h
  C.ImageBlurGaussian bg, opts.bg_blur or 12
  bg[0]

-- Remplit l'écran avec la texture de fond floutée (étirée ; la distorsion est masquée
-- par le flou). Utilisée quand l'image au premier plan ne couvre pas tout l'écran.
draw_background = (bgtex, alpha=255) ->
  source = rl.Rectangle 0, 0, bgtex.width, bgtex.height
  dest   = rl.Rectangle to_fb 0, 0, state.w, state.h
  C.DrawTexturePro bgtex, source, dest, (rl.Vector2 0, 0), 0, (rl.Color 255, 255, 255, alpha)

-- Dessine une diapo selon une `view` (rectangle en coords image, pouvant être plus grand
-- que l'image -> dézoom). L'image est mappée vers l'écran ; si elle ne le couvre pas
-- entièrement, le fond flou `slide.bg` (s'il existe) est dessiné d'abord.
draw_slide = (slide, view, alpha=255) ->
  scale = state.w / view.w           -- view est au ratio écran -> scale identique en x/y
  dx = -view.x * scale
  dy = -view.y * scale
  dw = slide.iw * scale
  dh = slide.ih * scale
  covers = dx <= 0.5 and dy <= 0.5 and dx + dw >= state.w - 0.5 and dy + dh >= state.h - 0.5
  if not covers and slide.bg
    draw_background slide.bg, alpha
  source = rl.Rectangle 0, 0, slide.iw, slide.ih
  dest   = rl.Rectangle to_fb dx, dy, dw, dh
  C.DrawTexturePro slide.tex, source, dest, (rl.Vector2 0, 0), 0, (rl.Color 255, 255, 255, alpha)
  dx, dy, scale

-- Cadre de debug (rect image -> écran) selon la vue courante.
draw_debug_rect = (view, rect_img, color) ->
  scale = state.w / view.w
  r = rl.Rectangle to_fb (rect_img.x - view.x)*scale, (rect_img.y - view.y)*scale,
                   rect_img.w*scale, rect_img.h*scale
  C.DrawRectangleLinesEx r, 3, color

begin_frame = ->
  refresh_size!        -- suit l'orientation/résolution courante de l'écran
  C.BeginDrawing!
end_frame   = -> C.EndDrawing!
clear       = -> C.ClearBackground BLACK
frame_time  = -> C.GetFrameTime!
time        = -> C.GetTime!
key_pressed = (k) -> C.IsKeyPressed k
-- Dépile le prochain caractère saisi (codepoint Unicode), en tenant compte de la disposition
-- de clavier active (bépo, azerty…) — contrairement à key_pressed qui suit la touche physique.
-- Renvoie 0 quand la file est vide.
char_pressed = -> C.GetCharPressed!
mouse_pressed = (b) -> C.IsMouseButtonPressed b
-- Abscisse souris ramenée au canevas logique (GetMouseX est en pixels framebuffer) : cohérent
-- avec screen! pour le découpage gauche/droite, même en portrait.
mouse_x = -> C.GetMouseX! * state.w / (state.fw > 0 and state.fw or state.w)
-- Nouveau toucher : front montant du nombre de points de contact. Avec le backend SDL de
-- raylib, le tactile Wayland (wl_touch) alimente cette API (GLFW, lui, ne la renseigne pas).
touch_pressed = ->
  n = C.GetTouchPointCount!
  was = state.touch_n or 0
  state.touch_n = n
  n > 0 and was == 0
touch_x = -> C.GetTouchX! * state.w / (state.fw > 0 and state.fw or state.w)
-- Fenêtre minimisée ou masquée (cas fiablement détectables d'invisibilité).
hidden = -> C.IsWindowState(rl.FLAG_WINDOW_MINIMIZED) or C.IsWindowHidden!
focused = -> C.IsWindowFocused!
wait = (s) -> sleep s

{ :init, :close, :should_close, :screen, :aspect, :load_texture, :unload_texture,
  :draw_slide, :draw_debug_rect, :make_background_image, :draw_background,
  :begin_frame, :end_frame, :clear, :frame_time, :time, :key_pressed, :char_pressed,
  :mouse_pressed, :mouse_x, :touch_pressed, :touch_x, :hidden, :focused, :wait, :sleep,
  :toggle_fullscreen, :rl }
