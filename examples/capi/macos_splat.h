/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * The splat library on Metal. macos_splat.m draws the scan of
 * window/capi_splat.mojo on the Mac's GPU, and macos_host.m calls it.
 *
 * The library keeps the scan, the camera and the controls, and it sorts the
 * splats. This code puts the scan on the GPU once, and each frame it copies the
 * draw order, when the sort changed it, and the view. Then it projects and shades
 * every splat, blends the quads, and shows the picture. splat.metal holds the
 * shaders.
 */
#ifndef THREEMOJO_MACOS_SPLAT_H
#define THREEMOJO_MACOS_SPLAT_H

#include <stddef.h>
#include <stdint.h>

#include "threemojo.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The functions of the library that the GPU code calls. A library that has no
 * splat functions is not drawn on Metal. */
typedef struct {
  int32_t (*prepare)(tm_app *);
  uint8_t *(*part)(tm_app *, int32_t);
  int32_t (*words)(const tm_app *, int32_t);
  int32_t (*info)(const tm_app *, int32_t);
  int32_t (*resize)(tm_app *, int32_t, int32_t);
} SplatApi;

typedef struct SplatMetal SplatMetal;

/* Make the passes for an app. The layer is a CAMetalLayer that shows the
 * frames, or NULL for a picture that splat_metal_read gives back. The size is
 * the size of the frame in pixels. Returns NULL, with the reason in error, if
 * this Mac has no Metal device or the shaders do not compile. */
SplatMetal *splat_metal_create(const SplatApi *api, tm_app *app, void *layer, int width,
                               int height, char *error, size_t error_size);

/* Wait for the GPU to finish, and free everything. */
void splat_metal_destroy(SplatMetal *metal);

/* The name of the GPU. It stays valid until splat_metal_destroy. */
const char *splat_metal_name(const SplatMetal *metal);

/* Change the size of the frame, in pixels. The library's frame must have this
 * size too. The scan stays. */
void splat_metal_resize(SplatMetal *metal, int width, int height);

/* Draw the frame of the last tm_splat_prepare. ready is its result: 0 when
 * there is a scan to draw, and the frame is then the background alone if it is
 * not. A layer shows the frame at the next refresh. Waits when three frames
 * are on the GPU already. Returns 0, or 1 when the frame was not drawn because
 * the layer's size is not the frame's. */
int splat_metal_draw(SplatMetal *metal, int32_t ready);

/* The nanoseconds that the GPU worked on frames, in all. */
uint64_t splat_metal_gpu_ns(const SplatMetal *metal);

/* The last frame as RGBA bytes, row by row from the top, width * height * 4.
 * It waits for the GPU. NULL for a metal that shows frames on a layer. The
 * bytes stay valid until the next call. */
const uint8_t *splat_metal_read(SplatMetal *metal);

#ifdef __cplusplus
}
#endif
#endif
