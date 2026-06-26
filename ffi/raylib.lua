-- Déclarations FFI minimales pour raylib 5.x (uniquement ce dont le diaporama a besoin).
-- Renvoie : { C = <clib>, new = <ffi.new>, Color/Rectangle/Vector2 = ctypes, PIXELFORMAT = ... }
local ffi = require("ffi")

ffi.cdef[[
typedef struct Vector2  { float x, y; } Vector2;
typedef struct Color    { unsigned char r, g, b, a; } Color;
typedef struct Rectangle{ float x, y, width, height; } Rectangle;
typedef struct Image    { void *data; int width; int height; int mipmaps; int format; } Image;
typedef struct Texture  { unsigned int id; int width; int height; int mipmaps; int format; } Texture;
typedef Texture Texture2D;

// Fenêtre / boucle
void InitWindow(int width, int height, const char *title);
void CloseWindow(void);
bool WindowShouldClose(void);
void SetTargetFPS(int fps);
void SetConfigFlags(unsigned int flags);
int  GetScreenWidth(void);
int  GetScreenHeight(void);
int  GetCurrentMonitor(void);
bool IsWindowFocused(void);
bool IsWindowHidden(void);
bool IsWindowState(unsigned int flag);
void WaitTime(double seconds);
int  GetMonitorWidth(int monitor);
int  GetMonitorHeight(int monitor);
void SetExitKey(int key);
void SetWindowSize(int width, int height);
void ToggleFullscreen(void);
bool IsWindowFullscreen(void);

// Dessin
void BeginDrawing(void);
void EndDrawing(void);
void ClearBackground(Color color);
double GetTime(void);
float  GetFrameTime(void);
bool   IsKeyPressed(int key);
int    GetCharPressed(void);
bool   IsMouseButtonPressed(int button);
int    GetMouseX(void);

// Images (CPU)
Image LoadImage(const char *fileName);
Image ImageCopy(Image image);
void  UnloadImage(Image image);
void  ImageResize(Image *image, int newWidth, int newHeight);
void  ImageFormat(Image *image, int newFormat);
void  ImageRotateCW(Image *image);
void  ImageRotateCCW(Image *image);
void  ImageFlipVertical(Image *image);
void  ImageFlipHorizontal(Image *image);
void  ImageBlurGaussian(Image *image, int blurSize);
void  ImageCrop(Image *image, Rectangle crop);

// Textures (GPU)
Texture2D LoadTextureFromImage(Image image);
void      UnloadTexture(Texture2D texture);
void      SetTextureFilter(Texture2D texture, int filter);
void      DrawTexturePro(Texture2D texture, Rectangle source, Rectangle dest,
                         Vector2 origin, float rotation, Color tint);
void      DrawRectangleLinesEx(Rectangle rec, float lineThick, Color color);
]]

local C = ffi.load(os.getenv("RAYLIB_SO") or "raylib")

return {
  C         = C,
  Color     = ffi.typeof("Color"),
  Rectangle = ffi.typeof("Rectangle"),
  Vector2   = ffi.typeof("Vector2"),
  Image     = ffi.typeof("Image"),
  -- Constantes utiles
  PIXELFORMAT_UNCOMPRESSED_R8G8B8  = 4,
  PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 = 7,
  FLAG_FULLSCREEN_MODE = 0x00000002,
  FLAG_WINDOW_RESIZABLE = 0x00000004,
  FLAG_VSYNC_HINT       = 0x00000040,
  FLAG_WINDOW_MINIMIZED = 0x00000200,
  TEXTURE_FILTER_BILINEAR = 1,
  KEY_ESCAPE = 256, KEY_RIGHT = 262, KEY_LEFT = 263, KEY_SPACE = 32, KEY_Q = 81,
  KEY_BACKSPACE = 259, KEY_F = 70,
  MOUSE_BUTTON_LEFT = 0, MOUSE_BUTTON_RIGHT = 1,
}
