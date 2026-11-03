/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * The village game on Metal. macos_village.m draws the frame that
 * window/capi_village.mojo prepares, on the Mac's GPU, and macos_host.m calls
 * it.
 *
 * The library does the shadow maps, the gathering, the light at the vertices
 * and the setup of each triangle. This code copies the vertices, the triangles,
 * the sky, the shadow maps and the maps to the GPU, rasterizes the triangles
 * and shades each pixel (village.metal). A library that takes the passes
 * (tm_village_passes) also has the weather and the night drawn with the sky,
 * the pond's water composed over the triangles, and the edges smoothed here.
 * The colors, and the depths if the library still needs them, are read back
 * into the library's images. The library then adds the rain and the
 * heads-up display on the CPU.
 */
#ifndef THREEMOJO_MACOS_VILLAGE_H
#define THREEMOJO_MACOS_VILLAGE_H

#include <stddef.h>
#include <stdint.h>

#include "threemojo.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The functions of the library that the GPU code calls. A library that has no
 * village functions is not drawn this way. */
typedef struct {
  int32_t (*passes)(tm_app *, int32_t); /* may be NULL: the CPU then draws the passes */
  int32_t (*prepare)(tm_app *);
  int64_t *(*ints)(tm_app *);
  float *(*floats)(tm_app *);
  int64_t *(*pointers)(tm_app *);
  const uint8_t *(*finish)(tm_app *);
} VillageApi;

typedef struct VillageMetal VillageMetal;

/* Make the passes for an app. Returns NULL, with the reason in error, if this
 * Mac has no Metal device or the shaders do not compile. */
VillageMetal *village_metal_create(const VillageApi *api, tm_app *app, char *error,
                                   size_t error_size);

/* Wait for the GPU to finish, and free everything. */
void village_metal_destroy(VillageMetal *metal);

/* The name of the GPU. It stays valid until village_metal_destroy. */
const char *village_metal_name(const VillageMetal *metal);

/* Draw the frame of the last tm_village_prepare, and read its colors and
 * depths into the library's images. Waits for the GPU. Returns 0, or 1 if the
 * frame has no size to draw. */
int village_metal_draw(VillageMetal *metal);

/* The nanoseconds that the GPU worked on frames, in all. */
uint64_t village_metal_gpu_ns(const VillageMetal *metal);

#ifdef __cplusplus
}
#endif
#endif
