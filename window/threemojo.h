/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * ThreeMojo's C ABI. The host owns the window, the loop and the clock.
 * Only scalars and one opaque handle cross this boundary.
 *
 * Every library has these functions: window/capi_core.mojo, which also builds
 * for WebAssembly, window/capi_scene.mojo, which runs the full renderer and
 * builds for the host only, window/capi_water.mojo, window/capi_splat.mojo and
 * window/capi_village.mojo, the village game, which builds for the host only.
 * Load one of them. The water and the splat libraries have the functions
 * below that say so.
 */
#ifndef THREEMOJO_H
#define THREEMOJO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Increases when a function changes. */
#define TM_ABI_VERSION 1
/* The largest frame side, in pixels. */
#define TM_MAX_SIDE 4096

typedef struct tm_app tm_app;

/* Event kinds. They are the values of ThreeMojo's InputKind. */
enum {
  TM_KEY_DOWN = 0,
  TM_POINTER_DOWN = 1,
  TM_POINTER_MOVE = 2,
  TM_POINTER_UP = 3,
  TM_WHEEL = 4,
  TM_KEY_UP = 6
};

/* Key codes. Printable keys are their ASCII codes. */
enum {
  TM_KEY_SPACE = 32,
  TM_KEY_ESCAPE = 27,
  TM_KEY_ARROW_UP = 256,
  TM_KEY_ARROW_DOWN = 257,
  TM_KEY_ARROW_LEFT = 258,
  TM_KEY_ARROW_RIGHT = 259,
  /* A key event has no modifiers, so Shift is a key of its own. The village
   * library runs while it is held. A library that has no use for it drops it. */
  TM_KEY_SHIFT = 260
};

/* The version of the ABI that the library was built with. */
int32_t tm_abi_version(void);

/* Start the runtime. Call it once, before every other function. */
void tm_init(void);

/* Make an app with a frame of width x height pixels. Returns NULL if a side
 * is outside 1..TM_MAX_SIDE. */
tm_app *tm_create(int32_t width, int32_t height);

/* Free an app and its frame. The handle must not be used again. */
void tm_destroy(tm_app *app);

/* Tell the app about one input event. x and y are pixels. detail is the key
 * code of a key event, the button of a pointer event (0 first, 1 middle,
 * 2 second, -1 none), or the notches of a wheel event, positive toward the
 * user. The space bar pauses and resumes the app. The village game takes it
 * for the jump instead. */
void tm_event(tm_app *app, int32_t kind, int32_t x, int32_t y, int32_t detail);

/* Move the app on by the time since the last step, in microseconds. */
void tm_step(tm_app *app, int32_t microseconds);

/* Draw the app and return the frame: RGBA, 8 bits a channel, row by row from
 * the top, tm_width * tm_height * 4 bytes. It stays valid until the next call
 * on this app. */
const uint8_t *tm_frame(tm_app *app);

int32_t tm_width(const tm_app *app);
int32_t tm_height(const tm_app *app);

/* Assets. A library that needs a file asks for it here. These functions are
 * not in every library: look for them with dlsym, or in the module's exports,
 * and call them only if they are there. The water library has them. It reads
 * its photograph from assets/pebbles.jpg where it can, and in a browser,
 * which has no files, the host gives it the bytes. */

/* Make room for size bytes in the library's memory. Returns NULL if size is
 * outside 1 to the library's most: 64 MiB for the water, 128 MiB for the
 * splats. Give the room back with tm_free. */
uint8_t *tm_alloc(int32_t size);

/* Give back room from tm_alloc. */
void tm_free(uint8_t *room);

/* Give the app a file: for the water, its pebble photograph, a JPEG, and for
 * the splats, a scan in any format whose first bytes name it. The app
 * copies the bytes before it returns. Returns 0 on success, and 1 if the
 * length is not positive or the bytes are not a file that the app can read.
 * The app is unchanged then. */
int32_t tm_asset(tm_app *app, const uint8_t *bytes, int32_t length);

/* A host's GPU. A host that has a GPU of its own, and cannot reach it from
 * Mojo, as a browser with WebGPU, draws the water's frame itself. The library
 * keeps the simulation, the ocean surface, the caustics and the glare's small
 * FFT. These functions are not in every library: the water library has them.
 * One frame goes like this:
 *
 *   tm_step(app, us);
 *   tm_gpu_prepare(app);          make the arrays of the frame
 *   ...copy the parts to the GPU, shade the frame, find the glints...
 *   tm_gpu_part(app, TM_GPU_SAMPLES) ...write the glints here...
 *   tm_gpu_glare(app);            spread the glints into the glare
 *   ...read TM_GPU_GRID, grade the frame, show it...
 *
 * water.wgsl, next to the web page, is a shader that does this. */

/* The parts of a prepared frame. */
enum {
  TM_GPU_SURFACE = 0,       /* surface texels: floats */
  TM_GPU_SURFACE_TABLE = 1, /* their level table: 64-bit integers */
  TM_GPU_RIPPLE = 2,        /* ripple normal texels: floats */
  TM_GPU_CAUSTIC = 3,       /* caustic texels: floats */
  TM_GPU_CAUSTIC_TABLE = 4, /* their level table: 64-bit integers */
  TM_GPU_PEBBLE = 5,        /* the photograph's texels: floats */
  TM_GPU_PEBBLE_TABLE = 6,  /* their level table: 64-bit integers */
  TM_GPU_VALUES = 7,        /* the frame values: floats */
  TM_GPU_SAMPLES = 8,       /* the host writes the glints here: floats */
  TM_GPU_GRID = 9           /* the glare after tm_gpu_glare: floats */
};

/* Numbers about a prepared frame. */
enum {
  TM_GPU_INFO_RIPPLE_SIDE = 0, /* ripple texels on one side */
  TM_GPU_INFO_GRID_WIDTH = 1,  /* the glare grid's width */
  TM_GPU_INFO_GRID_HEIGHT = 2  /* the glare grid's height */
};

/* Make the arrays that the host's GPU draws the next frame from, with the
 * camera that tm_frame uses. Call it after tm_step. The arrays stay valid
 * until the next call. Returns how many times the photograph has been packed,
 * which is 1 or more: upload the photograph again when the number changes.
 * Returns -1 if the water cannot be prepared, and the arrays are then those
 * of the last frame that could. */
int32_t tm_gpu_prepare(tm_app *app);

/* Spread the glints that the host wrote into TM_GPU_SAMPLES into the glare in
 * TM_GPU_GRID. Returns 0 on success, and 1 if tm_gpu_prepare has not run. */
int32_t tm_gpu_glare(tm_app *app);

/* Where a part is in memory, or NULL before tm_gpu_prepare and for a number
 * that is not a part. In a browser, take a new view of the module's memory
 * after every call into the module, because the memory can grow. */
uint8_t *tm_gpu_part(tm_app *app, int32_t which);

/* The size of a part in 32-bit words: a table of 64-bit integers counts two
 * words an entry. 0 before tm_gpu_prepare and for a number that is not a
 * part. */
int32_t tm_gpu_words(const tm_app *app, int32_t which);

/* One of the numbers about a prepared frame. 0 before tm_gpu_prepare. */
int32_t tm_gpu_info(const tm_app *app, int32_t which);

/* Gaussian splats. The splat library, window/capi_splat.mojo, draws a scan of
 * 445,409 splats: three tomatoes. It loads assets/tomatoes/tomatoes.v4.spz from
 * the folder it runs in, or a host gives it the bytes with tm_asset. These
 * functions are in that library only.
 *
 * tm_frame draws the scan on the CPU. A host that has a GPU draws it there. The
 * library keeps the scan, the camera and the controls, and it sorts the splats
 * back to front when the view has turned far enough. The host puts the scan
 * on its GPU once, and each frame it reads the draw order, when that changed,
 * and the view. One frame goes like this:
 *
 *   tm_step(app, us);
 *   if (tm_splat_prepare(app) == 0) {       the order and the view are ready
 *     if (tm_splat_info(app, TM_SPLAT_INFO_SCAN) changed)  copy the scan's arrays
 *     if (tm_splat_info(app, TM_SPLAT_INFO_ORDER) changed) copy the order
 *     ...copy the view, project and shade each splat, blend the quads...
 *   }
 *
 * splat.wgsl, next to the web page, and splat.metal, next to the macOS host,
 * are shaders that do this. */

/* Change the size of the frame, in pixels. The scan and the view stay: a host
 * that draws at the size of its window calls it when the window changes size.
 * Returns 0 on success, and 1 if a side is outside 1..TM_MAX_SIDE. The app is
 * unchanged then. */
int32_t tm_resize(tm_app *app, int32_t width, int32_t height);

/* The parts of a scan. */
enum {
  TM_SPLAT_CENTERS = 0,     /* 3 floats a splat */
  TM_SPLAT_COVARIANCES = 1, /* 6 floats a splat: xx, xy, xz, yy, yz, zz */
  TM_SPLAT_COLORS = 2,      /* 4 bytes a splat: RGBA */
  TM_SPLAT_SH1 = 3,         /* 9 coefficient bytes, 12 with padding, a splat */
  TM_SPLAT_SH2 = 4,         /* 15 coefficient bytes, 16 with padding, a splat */
  TM_SPLAT_SH3 = 5,         /* 21 coefficient bytes, 24 with padding, a splat */
  TM_SPLAT_ORDER = 6,       /* the splats' numbers, back to front: 32-bit integers */
  TM_SPLAT_VIEW = 7         /* TM_SPLAT_VIEW_FLOATS floats, as below */
};

/* Numbers about a scan. */
enum {
  TM_SPLAT_INFO_COUNT = 0,  /* splats */
  TM_SPLAT_INFO_DEGREE = 1, /* the scan's spherical harmonics degree, 0 to 3 */
  TM_SPLAT_INFO_SCAN = 2,   /* changes when a new scan is loaded */
  TM_SPLAT_INFO_ORDER = 3   /* changes when the order is sorted again */
};

/* The view is TM_SPLAT_VIEW_FLOATS floats: the model-view matrix at 0, the
 * projection matrix at 16, both column by column; the frame's width at 32 and
 * height at 33 in pixels; the eye at 34, 35 and 36; the degree at 37; the splat
 * count at 38; and the background color, 0 to 1, at 40, 41 and 42. */
#define TM_SPLAT_VIEW_FLOATS 48
#define TM_SPLAT_VIEW_BACKGROUND 40

/* Sort the splats and write the view, for the camera that tm_frame uses. Call
 * it after tm_step. The arrays stay valid until the next call. Returns 0 if the
 * order and the view are ready, and 1 if no scan is loaded or the view cannot
 * be made: the parts are then those of the last frame that could. */
int32_t tm_splat_prepare(tm_app *app);

/* Where a part is in memory, or NULL before a scan is loaded, for a band that
 * the scan does not have, for the order before the first tm_splat_prepare, and
 * for a number that is not a part. In a browser, take a new view of the
 * module's memory after every call into the module, because it can grow. */
uint8_t *tm_splat_part(tm_app *app, int32_t which);

/* The size of a part in 32-bit words. 0 where tm_splat_part is NULL. */
int32_t tm_splat_words(const tm_app *app, int32_t which);

/* One of the numbers about the scan. 0 before a scan is loaded, and for a
 * number that is not one. */
int32_t tm_splat_info(const tm_app *app, int32_t which);

/* The village game on a GPU (window/capi_village.mojo, with THREEMOJO_GPU=1).
 * The library does the shadow maps, the gathering, the light at the vertices,
 * the setup of each triangle and the sky's grid. The host draws the rest:
 *
 *   tm_step(app, microseconds);
 *   if (tm_village_prepare(app) == 1) {
 *     draw the triangles on the GPU, as the three arrays below describe them;
 *     copy the colors, and the depths if TM_VILLAGE_INT_DEPTH is 1, into the
 *         images named by TM_VILLAGE_POINTER_COLOR and TM_VILLAGE_POINTER_DEPTH;
 *     frame = tm_village_finish(app);        the rain and the HUD added, and
 *                                            the water, weather and smoothing
 *                                            unless the host took them
 *   }
 *
 * The three arrays are valid until the next tm_village_prepare. Every address
 * in the pointers is valid until then too. */

/* tm_village_ints: counts and sizes, 64-bit integers. */
enum {
  TM_VILLAGE_INT_WIDTH = 0,         /* the image's size, in pixels */
  TM_VILLAGE_INT_HEIGHT = 1,
  TM_VILLAGE_INT_VERTICES = 2,      /* vertices of 16 floats */
  TM_VILLAGE_INT_TRIANGLES = 3,
  TM_VILLAGE_INT_SKY_COLUMNS = 4,   /* the sky's grid, one RGB sample each */
  TM_VILLAGE_INT_SKY_ROWS = 5,
  TM_VILLAGE_INT_SKY_STEP = 6,      /* pixels between two samples */
  TM_VILLAGE_INT_FOG = 7,           /* 1 if the scene has fog */
  TM_VILLAGE_INT_STILL_ON = 8,      /* 1 if the still shadow map shades */
  TM_VILLAGE_INT_STILL_SIZE = 9,    /* texels on a side */
  TM_VILLAGE_INT_STILL_STRIDE = 10, /* floats in a row */
  TM_VILLAGE_INT_STILL_MADE = 11,   /* changes when the map is drawn again */
  TM_VILLAGE_INT_MOVING_ON = 12,
  TM_VILLAGE_INT_MOVING_SIZE = 13,
  TM_VILLAGE_INT_MOVING_STRIDE = 14,
  TM_VILLAGE_INT_MOVING_MADE = 15,
  TM_VILLAGE_INT_MAP_SLOTS = 16,    /* maps read at each pixel */
  TM_VILLAGE_INT_MAP_LEVELS = 17,   /* levels of all the maps */
  TM_VILLAGE_INT_MAP_FLOATS = 18,   /* floats of all the maps' texels */
  TM_VILLAGE_INT_PASSES = 19,       /* 1 if the host draws the passes below */
  TM_VILLAGE_INT_DEPTH = 20,        /* 1 if the host must return the depths */
  TM_VILLAGE_INT_COVER_COLUMNS = 21,/* the clouds' grid, one float a point */
  TM_VILLAGE_INT_COVER_ROWS = 22,
  TM_VILLAGE_INT_COVER_STEP = 23,   /* pixels between two points */
  TM_VILLAGE_INT_NIGHT_ON = 24,     /* 1 if the hour changes the sky */
  TM_VILLAGE_INT_SMOOTH_ON = 25,    /* 1 if the host smooths the edges */
  TM_VILLAGE_INT_WATER_ON = 26,     /* 1 if the host composes the water */
  TM_VILLAGE_INT_WATER_STEP = 27,   /* pixels between two shaded samples */
  TM_VILLAGE_INT_WATER_GRID_WIDTH = 28,
  TM_VILLAGE_INT_WATER_GRID_HEIGHT = 29,
  TM_VILLAGE_INT_WATER_SURFACE_MADE = 30, /* changes with the surface and the
                                             caustics */
  TM_VILLAGE_INT_WATER_RIPPLE_MADE = 31,  /* changes with the ripples */
  TM_VILLAGE_INT_WATER_BED_MADE = 32,     /* changes with the photograph */
  TM_VILLAGE_INT_WATER_SURFACE_FLOATS = 33,
  TM_VILLAGE_INT_WATER_RIPPLE_FLOATS = 34,
  TM_VILLAGE_INT_WATER_CAUSTIC_FLOATS = 35,
  TM_VILLAGE_INT_WATER_PEBBLE_FLOATS = 36,
  TM_VILLAGE_INT_WATER_WORDS = 37,
  TM_VILLAGE_INT_COUNT = 38
};

/* tm_village_floats: scalars, 32-bit floats. */
enum {
  TM_VILLAGE_FLOAT_EXPOSURE = 0,
  TM_VILLAGE_FLOAT_BIAS = 1,        /* the shadow bias, in meters */
  TM_VILLAGE_FLOAT_FOG_RED = 2,     /* the fog's color, linear */
  TM_VILLAGE_FLOAT_FOG_GREEN = 3,
  TM_VILLAGE_FLOAT_FOG_BLUE = 4,
  TM_VILLAGE_FLOAT_STILL_PER_METER = 5,
  TM_VILLAGE_FLOAT_MOVING_PER_METER = 6,
  TM_VILLAGE_FLOAT_WATER_EYE = 7,   /* 3 floats: the camera's place */
  TM_VILLAGE_FLOAT_WATER_CLIP = 10, /* 16 floats, column by column: the
                                       camera's projection and view */
  TM_VILLAGE_FLOAT_WATER_SHARE = 26,/* the water's own light, 0 to 1 */
  TM_VILLAGE_FLOAT_WATER_NIGHT = 27,/* 3 floats: bytes */
  TM_VILLAGE_FLOAT_COVER_GRAY = 30, /* 3 floats: bytes */
  TM_VILLAGE_FLOAT_COVER_FOG = 33,  /* 3 floats: bytes */
  TM_VILLAGE_FLOAT_COVER_VEIL = 36,
  TM_VILLAGE_FLOAT_COVER_MIST = 37,
  TM_VILLAGE_FLOAT_COVER_BRIGHT = 38,
  TM_VILLAGE_FLOAT_COVER_GLOOM = 39,
  TM_VILLAGE_FLOAT_NIGHT_DAY = 40,
  TM_VILLAGE_FLOAT_NIGHT_DUSK = 41,
  TM_VILLAGE_FLOAT_NIGHT_STARS = 42,
  TM_VILLAGE_FLOAT_NIGHT_D00 = 43,    /* 3 floats */
  TM_VILLAGE_FLOAT_NIGHT_ACROSS = 46, /* 3 floats */
  TM_VILLAGE_FLOAT_NIGHT_DOWN = 49,   /* 3 floats */
  TM_VILLAGE_FLOAT_NIGHT_GLOW = 52,   /* 3 floats: a gain */
  TM_VILLAGE_FLOAT_NIGHT_SKY = 55,    /* 3 floats: bytes */
  TM_VILLAGE_FLOAT_NIGHT_STAR_GRID = 58,
  TM_VILLAGE_FLOAT_NIGHT_STAR_RATE = 59,
  TM_VILLAGE_FLOAT_NIGHT_MOON = 60,   /* 3 floats */
  TM_VILLAGE_FLOAT_NIGHT_MOONLIT = 63,
  TM_VILLAGE_FLOAT_COUNT = 64
};

/* tm_village_pointers: addresses, 64-bit integers. */
enum {
  TM_VILLAGE_POINTER_VERTICES = 0,    /* float x 16 each: clip x y z w, ambient
                                         r g b, sun r g b, world x y z, a packed
                                         fog share, u, v */
  TM_VILLAGE_POINTER_CORNERS = 1,     /* int32 x 3 a triangle */
  TM_VILLAGE_POINTER_CODES = 2,       /* float a triangle: the map code, or -1 */
  TM_VILLAGE_POINTER_SKY = 3,         /* float x 3 a sample, linear */
  TM_VILLAGE_POINTER_STILL_DEPTH = 4, /* float, TM_VILLAGE_INT_STILL_STRIDE a row */
  TM_VILLAGE_POINTER_STILL_CLIP = 5,  /* 16 floats, column by column */
  TM_VILLAGE_POINTER_MOVING_DEPTH = 6,
  TM_VILLAGE_POINTER_MOVING_CLIP = 7,
  TM_VILLAGE_POINTER_MAP_TEXELS = 8,  /* float x 3 a texel, linear */
  TM_VILLAGE_POINTER_MAP_STARTS = 9,  /* int32 a level: where its texels start,
                                         in floats */
  TM_VILLAGE_POINTER_MAP_WIDTHS = 10, /* int32 a level */
  TM_VILLAGE_POINTER_MAP_HEIGHTS = 11,
  TM_VILLAGE_POINTER_MAP_FIRSTS = 12, /* int32 a map: its first level */
  TM_VILLAGE_POINTER_MAP_COUNTS = 13, /* int32 a map: its levels */
  TM_VILLAGE_POINTER_MAP_WRAPS_S = 14,/* int32 a map: 0 repeat, 1 clamp, 2 mirror */
  TM_VILLAGE_POINTER_MAP_WRAPS_T = 15,
  TM_VILLAGE_POINTER_COLOR = 16,      /* RGBA bytes, row by row from the top:
                                         the host writes the colors here */
  TM_VILLAGE_POINTER_DEPTH = 17,      /* float a pixel: the host writes the NDC
                                         depth here, infinity for the sky */
  TM_VILLAGE_POINTER_COVER = 18,      /* float a point of the clouds' grid */
  TM_VILLAGE_POINTER_WATER_SURFACE = 19,
  TM_VILLAGE_POINTER_WATER_RIPPLE = 20,
  TM_VILLAGE_POINTER_WATER_CAUSTIC = 21,
  TM_VILLAGE_POINTER_WATER_PEBBLE = 22,
  TM_VILLAGE_POINTER_WATER_WORDS = 23, /* uint32: frame words for the water
                                          shader (extensions/water/upload.mojo) */
  TM_VILLAGE_POINTER_COUNT = 24
};

/* A triangle's map code is its map's slot times TM_VILLAGE_LEVEL_CODE, plus the
 * level its pixels read. */
#define TM_VILLAGE_LEVEL_CODE 32

/* Let the host draw more of the frame. With the passes on (1), the host draws
 * the weather and the night with the sky, composes the pond's water over the
 * triangles and smooths the edges, each as the arrays of tm_village_prepare
 * switch it on (TM_VILLAGE_INT_NIGHT_ON, _WATER_ON and _SMOOTH_ON; the
 * weather is always on). tm_village_finish then leaves those passes out, and
 * TM_VILLAGE_INT_DEPTH is 0: the host need not return the depths. Call this
 * before tm_village_prepare; it takes effect at the next one. Returns 1 if
 * the app is one for a GPU, and 0 if not. */
int32_t tm_village_passes(tm_app *app, int32_t on);

/* Prepare the frame that the last tm_step left. Returns 1 if the three arrays
 * describe it, and 0 if the app is not one for a GPU (THREEMOJO_GPU is not 1)
 * or the frame cannot be drawn. */
int32_t tm_village_prepare(tm_app *app);

int64_t *tm_village_ints(tm_app *app);
float *tm_village_floats(tm_app *app);
int64_t *tm_village_pointers(tm_app *app);

/* End the frame that the GPU drew into the images, and return it as tm_frame
 * does. */
const uint8_t *tm_village_finish(tm_app *app);

#ifdef __cplusplus
}
#endif
#endif
