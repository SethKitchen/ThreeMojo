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
 * builds for the host only, window/capi_water.mojo and window/capi_splat.mojo.
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
  TM_KEY_ARROW_RIGHT = 259
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
 * user. The space bar pauses and resumes the app. */
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
 * outside 1..64 MiB. Give the room back with tm_free. */
uint8_t *tm_alloc(int32_t size);

/* Give back room from tm_alloc. */
void tm_free(uint8_t *room);

/* Give the app a file: for the water, its pebble photograph, a JPEG. The app
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

#ifdef __cplusplus
}
#endif
#endif
