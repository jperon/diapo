#include <stdio.h>
// Shim LD_PRELOAD : pose l'app_id Wayland (et la classe X11) de la fenêtre, que raylib
// ne définit pas — sans quoi GNOME/Mutter affiche « Inconnu » sans icône dans Alt+Tab.
// On intercepte glfwCreateWindow pour fixer les hints juste avant la création réelle.
//
// Subtilité : raylib (et donc libglfw) est chargé en RTLD_LOCAL par ffi.load, ce qui rend
// le vrai glfwCreateWindow invisible à RTLD_NEXT et glfwWindowHintString à RTLD_DEFAULT.
// On récupère donc les deux via un handle dlopen de libglfw par son SONAME (RTLD_NOLOAD
// renvoie le handle de la lib déjà chargée).
#include <dlfcn.h>
#include <stdlib.h>

extern "C" {

typedef void * (*create_window_t)(int, int, const char *, void *, void *);
typedef void   (*hint_string_t)(int, const char *);

// Valeurs des hints GLFW 3.4 (glfw3.h)
static const int GLFW_X11_CLASS_NAME = 0x00024001;
static const int GLFW_WAYLAND_APP_ID = 0x00026001;

static void * glfw_handle() {
  // Quelques SONAMEs possibles selon les versions.
  const char *names[] = { "libglfw.so.3", "libglfw.so", "libglfw.so.4", 0 };
  for (int i = 0; names[i]; i++) {
    void *h = dlopen(names[i], RTLD_NOW | RTLD_NOLOAD);
    if (h) return h;
  }
  return 0;
}

void * glfwCreateWindow(int width, int height, const char *title,
                        void *monitor, void *share) {
  void *glfw = glfw_handle();
  create_window_t real = glfw ? (create_window_t) dlsym(glfw, "glfwCreateWindow") : 0;
  if (!real) real = (create_window_t) dlsym(RTLD_NEXT, "glfwCreateWindow");

  hint_string_t hint = glfw ? (hint_string_t) dlsym(glfw, "glfwWindowHintString") : 0;
  if (hint) {
    const char *id = getenv("DIAPO_APP_ID");
    if (!id || !*id) id = "diapo";
    hint(GLFW_WAYLAND_APP_ID, id);
    hint(GLFW_X11_CLASS_NAME, id);
    if (getenv("DIAPO_DEBUG")) fprintf(stderr, "diapo_appid: app_id='%s' posé\n", id);
  } else if (getenv("DIAPO_DEBUG")) {
    fprintf(stderr, "diapo_appid: glfwWindowHintString introuvable\n");
  }
  return real(width, height, title, monitor, share);
}

} // extern "C"
