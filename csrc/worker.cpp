// Worker de préchargement asynchrone : crée un thread avec son PROPRE lua_State (les
// états Lua ne sont pas partageables entre threads) qui exécute un script bootstrap.
// Le script fait tout le travail CPU lourd (décodage image, EXIF, détection, plan, fond
// flou) via FFI, et communique avec le thread principal par une struct DiapoJob partagée.
// Le thread principal ne garde que l'upload GPU des textures.
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
#include "diapo_job.h"

#define DIAPO_API extern "C" __attribute__((visibility("default")))

// Barrière mémoire complète, appelée depuis le Lua des deux threads autour des
// transitions du drapeau `state` (publication des données avant le drapeau, et lecture
// des données après le drapeau). Garantit l'ordre sur les architectures à modèle mémoire
// faible (ARM…), où le simple ordre des écritures ne suffit pas.
DIAPO_API void diapo_membar(void) { __sync_synchronize(); }

typedef struct {
  pthread_t thread;
  int       started;
  char      bootstrap[4096];
  DiapoJob  job;
} DiapoWorker;

static void *worker_main(void *arg) {
  DiapoWorker *w = (DiapoWorker *)arg;

  lua_State *L = luaL_newstate();
  if (!L) { w->job.state = 3; return NULL; }
  luaL_openlibs(L);

  // Expose le pointeur de job au script bootstrap via la globale DIAPO_JOB.
  lua_pushlightuserdata(L, &w->job);
  lua_setglobal(L, "DIAPO_JOB");

  if (luaL_loadfile(L, w->bootstrap) != 0 || lua_pcall(L, 0, 0, 0) != 0) {
    const char *err = lua_tostring(L, -1);
    fprintf(stderr, "diapo worker: %s\n", err ? err : "erreur inconnue");
    w->job.state = 3;
  }

  lua_close(L);
  return NULL;
}

// Démarre le worker. `bootstrap` = chemin du script Lua de boucle. Renvoie un handle
// opaque, ou NULL en cas d'échec (l'appelant bascule alors en mode synchrone).
DIAPO_API DiapoWorker *diapo_worker_start(const char *bootstrap) {
  DiapoWorker *w = (DiapoWorker *)calloc(1, sizeof(DiapoWorker));
  if (!w) return NULL;
  strncpy(w->bootstrap, bootstrap, sizeof(w->bootstrap) - 1);
  w->job.state = 0;
  if (pthread_create(&w->thread, NULL, worker_main, w) != 0) {
    free(w);
    return NULL;
  }
  w->started = 1;
  return w;
}

// Accès à la struct de job partagée.
DIAPO_API DiapoJob *diapo_worker_job(DiapoWorker *w) {
  return w ? &w->job : NULL;
}

// Arrête le worker proprement (demande la sortie + join + libération).
DIAPO_API void diapo_worker_stop(DiapoWorker *w) {
  if (!w) return;
  if (w->started) {
    __atomic_store_n(&w->job.state, 9, __ATOMIC_RELEASE);
    pthread_join(w->thread, NULL);
  }
  free(w);
}
