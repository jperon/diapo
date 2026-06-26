// Wrapper exposant facedetect_cnn en `extern "C"` afin que le FFI de LuaJIT
// puisse le charger sans avoir à gérer le name-mangling C++.
//
// libfacedetection déclare facedetect_cnn sans `extern "C"` ; le symbole est
// donc mangled dans le .so. On le réexpose ici sous un nom C stable.
#include "facedetectcnn.h"

#define DIAPO_VIS __attribute__((visibility("default")))

extern "C" {

// Taille de buffer requise par libfacedetection (voir FACEDETECTION_RESULT_BUFFER_SIZE).
DIAPO_VIS int diapo_facedetect_buffer_size() {
    return FACEDETECTION_RESULT_BUFFER_SIZE;
}

// Nombre de shorts par enregistrement de visage (FACEDETECTION_RESULT_STRIDE_SHORTS).
DIAPO_VIS int diapo_facedetect_stride_shorts() {
    return FACEDETECTION_RESULT_STRIDE_SHORTS;
}

// Détection. `image` doit être en BGR contigu, `step` = octets par ligne.
// Retourne le pointeur résultat (== result_buffer) : result_buffer[0] = nb de visages,
// puis pour le visage i : short* p = ((short*)(result_buffer+1)) + stride*i
//   p[0]=score, p[1..4]=x,y,w,h, p[5..14]=5 points de repère.
DIAPO_VIS int * diapo_facedetect(unsigned char *result_buffer,
                       unsigned char *image, int width, int height, int step) {
    return facedetect_cnn(result_buffer, image, width, height, step);
}

} // extern "C"
