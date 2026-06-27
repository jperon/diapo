// Structure d'échange entre le thread principal et le thread worker de préchargement.
// IMPORTANT : la disposition doit rester STRICTEMENT identique au ffi.cdef de
// ffi/jobdef.lua (mêmes types, même ordre).
#ifndef DIAPO_JOB_H
#define DIAPO_JOB_H

#define DIAPO_MAX_FACES 64

typedef struct {
  int    state;          // 0 idle, 1 requête, 2 prêt, 3 erreur
  int    quit;           // 1 : demande d'arrêt (champ distinct de state, jamais écrasé par
                         // le worker -> pas de course entre la fin d'un job et l'arrêt)
  char   path[4096];

  // Paramètres d'entrée (remplis par le thread principal)
  double aspect;
  int    reverse;
  int    detect_width;
  int    min_score;
  int    rotate;         // 1 : tente aussi la détection sur ±90°
  double margin;
  double zoom_out;
  double zoom_max;
  double zoom_min;
  int    keep_eyes;
  int    face_focus;     // 1 : ne cadrer qu'un seul visage (tiré au hasard par le worker)
  int    face_delta_max; // écart de score max sous le meilleur pour rester éligible (0 = illimité)
  int    make_bg;
  int    bg_width;
  int    bg_blur;
  int    arc_dir_mode;   // sens d'arc tirables : 0 toward, 1 away, 2 both
  int    override_nfaces;// >0 : visages manuels fournis dans faces[] (normalisés), détection sautée

  // Résultats (remplis par le worker)
  void  *img_data;       // pixels de l'Image raylib (premier plan)
  int    img_w, img_h, img_format;
  void  *bg_data;        // pixels de l'Image de fond floutée (ou NULL)
  int    bg_w, bg_h, bg_format;

  // Plan Ken Burns calculé (rectangles début/fin, coords image)
  double start_x, start_y, start_w, start_h;
  double finish_x, finish_y, finish_w, finish_h;

  int    nfaces;
  int    focus;          // index (1-based) du visage cadré serré, 0 = tous (sortie worker)
  double arc_dx, arc_dy; // composantes de la bosse d'arc (signe inclus)
  int    arc_sign;       // sens tiré (+1/-1), mémorisé pour le recalcul au resize
  float  faces[DIAPO_MAX_FACES * 5];   // x,y,w,h,score par visage (entrée override / sortie debug)
} DiapoJob;

#endif
