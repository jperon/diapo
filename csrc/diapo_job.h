// Structure d'échange entre le thread principal et le thread worker de préchargement.
// IMPORTANT : la disposition doit rester STRICTEMENT identique au ffi.cdef de
// ffi/jobdef.lua (mêmes types, même ordre).
#ifndef DIAPO_JOB_H
#define DIAPO_JOB_H

#define DIAPO_MAX_FACES 64

typedef struct {
  int    state;          // 0 idle, 1 requête, 2 prêt, 3 erreur, 9 quitter
  char   path[4096];

  // Paramètres d'entrée (remplis par le thread principal)
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

  // Résultats (remplis par le worker)
  void  *img_data;       // pixels de l'Image raylib (premier plan)
  int    img_w, img_h, img_format;
  void  *bg_data;        // pixels de l'Image de fond floutée (ou NULL)
  int    bg_w, bg_h, bg_format;

  // Plan Ken Burns calculé (rectangles début/fin, coords image)
  double start_x, start_y, start_w, start_h;
  double finish_x, finish_y, finish_w, finish_h;

  int    nfaces;
  float  faces[DIAPO_MAX_FACES * 4];   // x,y,w,h par visage (pour le mode debug)
} DiapoJob;

#endif
