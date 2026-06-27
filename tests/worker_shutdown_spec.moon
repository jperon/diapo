-- Régression : arrêt du worker pendant qu'un job est en cours de traitement. Le worker ne
-- doit pas écraser la demande d'arrêt par la publication de son résultat (sinon join bloque
-- -> image figée à la sortie sur « Q »). Chien de garde alarm() : si join bloque, SIGALRM
-- termine le process (échec non bloquant pour la suite) au lieu de geler.
ffi = require "ffi"
ok_jd = pcall require, "jobdef"
ffi.cdef [[
  typedef struct DiapoWorker DiapoWorker;
  DiapoWorker * diapo_worker_start(const char *bootstrap);
  DiapoJob *    diapo_worker_job(DiapoWorker *w);
  void          diapo_worker_stop(DiapoWorker *w);
  void          diapo_membar(void);
  unsigned int  usleep(unsigned int usec);
  unsigned int  alarm(unsigned int seconds);
]]

root = os.getenv("DIAPO_ROOT") or "."
ok_lib, C = pcall ffi.load, root .. "/lib/libfacedetection.so"
has_data = io.open "testdata/face.jpg", "r"
has_data\close! if has_data

passed, failed = 0, 0
if ok_jd and ok_lib and has_data
  ffi.C.alarm 20          -- chien de garde : tue le process si un join bloque
  start = -> C.diapo_worker_start root .. "/src/worker.lua"
  w = start!
  assert w != nil, "worker start"
  j = C.diapo_worker_job w
  for iter = 1, 10
    path = "testdata/face.jpg"
    ffi.copy j.path, path, #path
    j.path[#path] = 0
    j.aspect = 1.7
    j.detect_width, j.min_score, j.rotate = 480, 70, 1   -- rotate -> process() plus long
    j.margin, j.zoom_out, j.zoom_max, j.zoom_min = 0.35, 1.0, 0, 0
    j.keep_eyes, j.make_bg, j.bg_width, j.bg_blur = 1, 0, 320, 12
    j.img_data, j.bg_data = nil, nil
    C.diapo_membar!
    j.state = 1                       -- soumission
    C.usleep 8000                     -- laisse le worker entrer dans process()
    C.diapo_worker_stop w             -- doit revenir (pas de deadlock)
    if iter < 10
      w = start!
      j = C.diapo_worker_job w
  ffi.C.alarm 0           -- désarme le chien de garde : tout s'est arrêté proprement
  passed += 1
  print "worker_shutdown: arrêt propre sur 10 cycles"
else
  print "worker_shutdown: (lib/testdata indisponible : test sauté)"

print "worker_shutdown: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
