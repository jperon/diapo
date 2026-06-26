-- Définition FFI de DiapoJob, partagée par le thread principal (async.moon) et le worker
-- (worker.moon). DOIT rester identique à csrc/diapo_job.h.
local ffi = require("ffi")

ffi.cdef[[
typedef struct {
  int    state;
  char   path[4096];

  double aspect;
  int    reverse;
  int    detect_width;
  int    min_score;
  double margin;
  double zoom_out;
  double zoom_max;
  double zoom_min;
  int    keep_eyes;
  int    make_bg;
  int    bg_width;
  int    bg_blur;

  void  *img_data;
  int    img_w, img_h, img_format;
  void  *bg_data;
  int    bg_w, bg_h, bg_format;

  double start_x, start_y, start_w, start_h;
  double finish_x, finish_y, finish_w, finish_h;

  int    nfaces;
  float  faces[256];
} DiapoJob;
]]

return { MAX_FACES = 64 }
