/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * The village game on Metal. See macos_village.h, and village.metal for the
 * shaders. build.sh turns village.metal into village_msl.h, a C string, and the
 * shaders compile when the host starts, so no Metal toolchain is needed to
 * build the host.
 *
 * A frame is one render pass: a triangle that fills the image with the sky, with
 * the weather and the night over it, and then one indexed draw of every
 * triangle, with a depth test. Two compute passes follow. The first shades the
 * pond's water on a grid of samples. The second tests each pixel against the
 * triangles' depth, mixes the pixel from the four samples round it, and writes
 * it. A third smooths the edges. The call waits for the GPU and reads the
 * colors into the library's own image, so the library goes on with the rain and
 * the heads-up display.
 *
 * A library that does not take the passes (tm_village_passes) draws the weather,
 * the water and the smoothing on the CPU. The host then reads the depths back
 * too, as the library asks (TM_VILLAGE_INT_DEPTH).
 *
 * Everything is copied to buffers that the call reuses from frame to frame, so
 * a frame costs a copy and no allocation. The shadow maps and the maps that
 * are read at each pixel are copied again only when the library made them again.
 */
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

#include "macos_village.h"
#include "village_msl.h"

#define VERTEX_BYTES 64
#define CORNER_BYTES 12
#define CODE_BYTES 4
#define SKY_SAMPLE_BYTES 12

/* The frame's numbers, as village.metal's Frame. */
typedef struct {
  float still_clip[16];
  float moving_clip[16];
  float fog_color[4];
  float exposure;
  float bias;
  float still_per_meter;
  float moving_per_meter;
  int32_t width;
  int32_t height;
  int32_t fog;
  int32_t still_on;
  int32_t still_size;
  int32_t still_stride;
  int32_t moving_on;
  int32_t moving_size;
  int32_t moving_stride;
  int32_t sky_columns;
  int32_t sky_rows;
  int32_t sky_step;
} VillageFrame;

/* The numbers of the passes after the triangles, as village.metal's Post. */
typedef struct {
  float water_clip[16];
  float water_eye[4];
  float water_night[4];
  float cover_gray[4];
  float cover_fog[4];
  float cover_misc[4];
  float night_a[4];
  float night_d00[4];
  float night_across[4];
  float night_down[4];
  float night_glow[4];
  float night_sky[4];
  int32_t cover_ints[4];
  int32_t water_ints[4];
  int32_t flags[4];
} VillagePost;

@interface VillageRenderer : NSObject {
@public
  VillageApi api;
  tm_app *app;
  id<MTLDevice> device;
  id<MTLCommandQueue> queue;
  id<MTLRenderPipelineState> sky;
  id<MTLRenderPipelineState> scene;
  id<MTLDepthStencilState> behind; /* the sky: no test, no write */
  id<MTLDepthStencilState> nearer; /* the triangles: less or equal, and write */
  id<MTLComputePipelineState> water_grid, water_compose, smooth;
  id<MTLTexture> color;            /* RGBA bytes: the triangles, and then the water */
  id<MTLTexture> depth_out;        /* NDC depth floats, which the water tests against */
  id<MTLTexture> depth_test;       /* the depth buffer of the pass */
  id<MTLTexture> smoothed;         /* the image after the smoothing of edges */
  id<MTLBuffer> color_out, depth_read; /* the images, copied out of the textures by the GPU */
  id<MTLBuffer> vertices, corners, codes, grid;
  id<MTLBuffer> cover;               /* the clouds' grid */
  id<MTLBuffer> water_surface, water_ripple, water_caustic, water_pebble, water_words, water_samples;
  int64_t surface_made, ripple_made, bed_made; /* which copies of the water's tables the GPU holds */
  id<MTLBuffer> still, moving;
  id<MTLBuffer> texels, starts, widths, heights, firsts, counts, wraps_s, wraps_t;
  int width, height;
  int64_t still_made, moving_made;   /* which draw of each map the GPU holds */
  int64_t maps_made[3];              /* the maps' slots, levels and floats on the GPU */
  uint64_t gpu_ns;
  bool failed;                       /* a failure was printed already */
}
@end

@implementation VillageRenderer
@end

static void fail(char *error, size_t size, NSString *reason) {
  if (error && size > 0) snprintf(error, size, "%s", reason.UTF8String);
}

/* A buffer of at least `length` bytes: the one given, or a new one with room to
 * grow. A buffer is never empty, because a shader that reads none still binds
 * one. */
static id<MTLBuffer> room(VillageRenderer *r, id<MTLBuffer> buffer, size_t length) {
  if (length < 16) length = 16;
  if (buffer && buffer.length >= length) return buffer;
  return [r->device newBufferWithLength:length + length / 4 options:MTLResourceStorageModeShared];
}

/* Copy bytes of the library into a buffer. */
static id<MTLBuffer> upload(VillageRenderer *r, id<MTLBuffer> buffer, int64_t address, size_t length) {
  buffer = room(r, buffer, length);
  if (length > 0 && address) memcpy(buffer.contents, (const void *)(intptr_t)address, length);
  return buffer;
}

static id<MTLTexture> make_texture(VillageRenderer *r, MTLPixelFormat format, MTLStorageMode storage,
                                   MTLTextureUsage usage) {
  MTLTextureDescriptor *descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                         width:(NSUInteger)r->width
                                                        height:(NSUInteger)r->height
                                                     mipmapped:NO];
  descriptor.usage = usage;
  descriptor.storageMode = storage;
  return [r->device newTextureWithDescriptor:descriptor];
}

static void make_targets(VillageRenderer *r, int width, int height) {
  r->width = width;
  r->height = height;
  /* The compute passes read and write the color and read the depth. */
  MTLTextureUsage usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
  r->color = make_texture(r, MTLPixelFormatRGBA8Unorm, MTLStorageModePrivate, usage);
  r->depth_out = make_texture(r, MTLPixelFormatR32Float, MTLStorageModePrivate, usage);
  r->depth_test = make_texture(r, MTLPixelFormatDepth32Float, MTLStorageModePrivate, MTLTextureUsageRenderTarget);
  r->smoothed = make_texture(r, MTLPixelFormatRGBA8Unorm, MTLStorageModePrivate,
                             MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite);
  /* A CPU reads a texture slowly, because the GPU lays it out in tiles. A buffer
   * is a plain array, and the GPU copies the texture into it in a blit. */
  r->color_out = [r->device newBufferWithLength:(NSUInteger)width * height * 4
                                        options:MTLResourceStorageModeShared];
  r->depth_read = [r->device newBufferWithLength:(NSUInteger)width * height * 4
                                         options:MTLResourceStorageModeShared];
}

static id<MTLRenderPipelineState> make_pipeline(VillageRenderer *r, id<MTLLibrary> library,
                                                NSString *vertex, NSString *fragment, char *error,
                                                size_t error_size) {
  MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:vertex];
  descriptor.fragmentFunction = [library newFunctionWithName:fragment];
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  descriptor.colorAttachments[1].pixelFormat = MTLPixelFormatR32Float;
  descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
  NSError *failure = nil;
  id<MTLRenderPipelineState> state = [r->device newRenderPipelineStateWithDescriptor:descriptor error:&failure];
  if (!state) fail(error, error_size, failure.localizedDescription);
  return state;
}

static id<MTLComputePipelineState> make_compute(VillageRenderer *r, id<MTLLibrary> library, NSString *name,
                                                char *error, size_t error_size) {
  NSError *failure = nil;
  id<MTLFunction> function = [library newFunctionWithName:name];
  id<MTLComputePipelineState> state = [r->device newComputePipelineStateWithFunction:function error:&failure];
  if (!state) fail(error, error_size, failure.localizedDescription);
  return state;
}

VillageMetal *village_metal_create(const VillageApi *api, tm_app *app, char *error, size_t error_size) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      fail(error, error_size, @"this Mac has no Metal device");
      return NULL;
    }
    VillageRenderer *r = [VillageRenderer new];
    r->api = *api;
    r->app = app;
    r->device = device;
    r->queue = [device newCommandQueue];
    r->still_made = r->moving_made = -1;
    r->surface_made = r->ripple_made = r->bed_made = -1;
    if (device.readWriteTextureSupport == MTLReadWriteTextureTierNone) {
      fail(error, error_size, @"this GPU cannot read and write a texture in one pass");
      return NULL;
    }
    for (int k = 0; k < 3; k++) r->maps_made[k] = -1;

    MTLCompileOptions *options = [MTLCompileOptions new];
    /* Exact pow, sqrt and floor, as the CPU rounds them. */
    if (@available(macOS 15.0, *)) options.mathMode = MTLMathModeSafe;
    else options.fastMathEnabled = NO;
    NSError *failure = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:@(VILLAGE_MSL) options:options error:&failure];
    if (!library) {
      fail(error, error_size, [@"village.metal does not compile: "
                                  stringByAppendingString:failure.localizedDescription]);
      return NULL;
    }
    r->sky = make_pipeline(r, library, @"sky_vertex", @"sky_fragment", error, error_size);
    r->scene = make_pipeline(r, library, @"scene_vertex", @"scene_fragment", error, error_size);
    if (!r->sky || !r->scene) return NULL;
    r->water_grid = make_compute(r, library, @"water_grid", error, error_size);
    r->water_compose = make_compute(r, library, @"water_compose", error, error_size);
    r->smooth = make_compute(r, library, @"smooth_edges", error, error_size);
    if (!r->water_grid || !r->water_compose || !r->smooth) return NULL;
    /* Take the passes after the triangles, if the library has them. */
    if (api->passes) api->passes(app, 1);

    MTLDepthStencilDescriptor *none = [MTLDepthStencilDescriptor new];
    none.depthCompareFunction = MTLCompareFunctionAlways;
    none.depthWriteEnabled = NO;
    r->behind = [device newDepthStencilStateWithDescriptor:none];
    MTLDepthStencilDescriptor *test = [MTLDepthStencilDescriptor new];
    test.depthCompareFunction = MTLCompareFunctionLessEqual;
    test.depthWriteEnabled = YES;
    r->nearer = [device newDepthStencilStateWithDescriptor:test];
    return (VillageMetal *)CFBridgingRetain(r);
  }
}

static VillageRenderer *renderer(const VillageMetal *metal) {
  return (__bridge VillageRenderer *)(const void *)metal;
}

void village_metal_destroy(VillageMetal *metal) {
  if (metal) CFRelease(metal);
}

const char *village_metal_name(const VillageMetal *metal) {
  return renderer(metal)->device.name.UTF8String;
}

uint64_t village_metal_gpu_ns(const VillageMetal *metal) { return renderer(metal)->gpu_ns; }

/* Copy a shadow map to the GPU if the library drew it again. */
static void load_shadow(VillageRenderer *r, int64_t on, int64_t made, int64_t stride, int64_t address,
                        id<MTLBuffer> __strong *buffer, int64_t *held) {
  if (!on) {
    *buffer = room(r, *buffer, 16);
    return;
  }
  if (made == *held && *buffer) return;
  *buffer = upload(r, *buffer, address, (size_t)(stride * stride) * 4);
  *held = made;
}

/* Copy the maps that are read at each pixel to the GPU if there are more. */
static void load_maps(VillageRenderer *r, const int64_t *n, const int64_t *p) {
  int64_t slots = n[TM_VILLAGE_INT_MAP_SLOTS];
  int64_t levels = n[TM_VILLAGE_INT_MAP_LEVELS];
  int64_t floats = n[TM_VILLAGE_INT_MAP_FLOATS];
  if (slots == r->maps_made[0] && levels == r->maps_made[1] && floats == r->maps_made[2] && r->texels) {
    return;
  }
  r->texels = upload(r, r->texels, p[TM_VILLAGE_POINTER_MAP_TEXELS], (size_t)floats * 4);
  r->starts = upload(r, r->starts, p[TM_VILLAGE_POINTER_MAP_STARTS], (size_t)levels * 4);
  r->widths = upload(r, r->widths, p[TM_VILLAGE_POINTER_MAP_WIDTHS], (size_t)levels * 4);
  r->heights = upload(r, r->heights, p[TM_VILLAGE_POINTER_MAP_HEIGHTS], (size_t)levels * 4);
  r->firsts = upload(r, r->firsts, p[TM_VILLAGE_POINTER_MAP_FIRSTS], (size_t)slots * 4);
  r->counts = upload(r, r->counts, p[TM_VILLAGE_POINTER_MAP_COUNTS], (size_t)slots * 4);
  r->wraps_s = upload(r, r->wraps_s, p[TM_VILLAGE_POINTER_MAP_WRAPS_S], (size_t)slots * 4);
  r->wraps_t = upload(r, r->wraps_t, p[TM_VILLAGE_POINTER_MAP_WRAPS_T], (size_t)slots * 4);
  r->maps_made[0] = slots;
  r->maps_made[1] = levels;
  r->maps_made[2] = floats;
}

/* Copy `count` floats of the library's scalars. */
static void take(float *to, const float *from, int count) {
  for (int k = 0; k < count; k++) to[k] = from[k];
}

/* The numbers of the passes after the triangles, from the library's arrays. With
 * the passes off, the block is zero and its first flag says so. */
static void fill_post(VillagePost *post, const int64_t *n, const float *f) {
  memset(post, 0, sizeof *post);
  if (!n[TM_VILLAGE_INT_PASSES]) return;
  take(post->water_clip, f + TM_VILLAGE_FLOAT_WATER_CLIP, 16);
  take(post->water_eye, f + TM_VILLAGE_FLOAT_WATER_EYE, 3);
  take(post->water_night, f + TM_VILLAGE_FLOAT_WATER_NIGHT, 3);
  post->water_night[3] = f[TM_VILLAGE_FLOAT_WATER_SHARE];
  take(post->cover_gray, f + TM_VILLAGE_FLOAT_COVER_GRAY, 3);
  post->cover_gray[3] = f[TM_VILLAGE_FLOAT_COVER_VEIL];
  take(post->cover_fog, f + TM_VILLAGE_FLOAT_COVER_FOG, 3);
  post->cover_fog[3] = f[TM_VILLAGE_FLOAT_COVER_MIST];
  post->cover_misc[0] = f[TM_VILLAGE_FLOAT_COVER_BRIGHT];
  post->cover_misc[1] = f[TM_VILLAGE_FLOAT_COVER_GLOOM];
  post->night_a[0] = f[TM_VILLAGE_FLOAT_NIGHT_DAY];
  post->night_a[1] = f[TM_VILLAGE_FLOAT_NIGHT_DUSK];
  post->night_a[2] = f[TM_VILLAGE_FLOAT_NIGHT_STARS];
  post->night_a[3] = f[TM_VILLAGE_FLOAT_NIGHT_STAR_GRID];
  take(post->night_d00, f + TM_VILLAGE_FLOAT_NIGHT_D00, 3);
  post->night_d00[3] = f[TM_VILLAGE_FLOAT_NIGHT_STAR_RATE];
  take(post->night_across, f + TM_VILLAGE_FLOAT_NIGHT_ACROSS, 3);
  take(post->night_down, f + TM_VILLAGE_FLOAT_NIGHT_DOWN, 3);
  take(post->night_glow, f + TM_VILLAGE_FLOAT_NIGHT_GLOW, 3);
  take(post->night_sky, f + TM_VILLAGE_FLOAT_NIGHT_SKY, 3);
  post->cover_ints[0] = (int32_t)n[TM_VILLAGE_INT_COVER_COLUMNS];
  post->cover_ints[1] = (int32_t)n[TM_VILLAGE_INT_COVER_ROWS];
  post->cover_ints[2] = (int32_t)n[TM_VILLAGE_INT_COVER_STEP];
  post->cover_ints[3] = (int32_t)n[TM_VILLAGE_INT_NIGHT_ON];
  post->water_ints[0] = (int32_t)n[TM_VILLAGE_INT_WATER_ON];
  post->water_ints[1] = (int32_t)n[TM_VILLAGE_INT_WATER_STEP];
  post->water_ints[2] = (int32_t)n[TM_VILLAGE_INT_WATER_GRID_WIDTH];
  post->water_ints[3] = (int32_t)n[TM_VILLAGE_INT_WATER_GRID_HEIGHT];
  post->flags[0] = 1;
  post->flags[1] = (int32_t)n[TM_VILLAGE_INT_SMOOTH_ON];
}

/* Copy the clouds' grid, and the water's tables that the library made again. */
static void load_post(VillageRenderer *r, const int64_t *n, const int64_t *p) {
  if (!n[TM_VILLAGE_INT_PASSES]) {
    r->cover = room(r, r->cover, 16);
    r->water_samples = room(r, r->water_samples, 16);
    r->water_words = room(r, r->water_words, 16);
    r->water_surface = room(r, r->water_surface, 16);
    r->water_ripple = room(r, r->water_ripple, 16);
    r->water_caustic = room(r, r->water_caustic, 16);
    r->water_pebble = room(r, r->water_pebble, 16);
    return;
  }
  r->cover = upload(r, r->cover, p[TM_VILLAGE_POINTER_COVER],
                    (size_t)(n[TM_VILLAGE_INT_COVER_COLUMNS] * n[TM_VILLAGE_INT_COVER_ROWS]) * 4);
  if (!n[TM_VILLAGE_INT_WATER_ON]) return;
  if (n[TM_VILLAGE_INT_WATER_SURFACE_MADE] != r->surface_made || !r->water_surface || !r->water_caustic) {
    r->water_surface = upload(r, r->water_surface, p[TM_VILLAGE_POINTER_WATER_SURFACE],
                              (size_t)n[TM_VILLAGE_INT_WATER_SURFACE_FLOATS] * 4);
    r->water_caustic = upload(r, r->water_caustic, p[TM_VILLAGE_POINTER_WATER_CAUSTIC],
                              (size_t)n[TM_VILLAGE_INT_WATER_CAUSTIC_FLOATS] * 4);
    r->surface_made = n[TM_VILLAGE_INT_WATER_SURFACE_MADE];
  }
  if (n[TM_VILLAGE_INT_WATER_RIPPLE_MADE] != r->ripple_made || !r->water_ripple) {
    r->water_ripple = upload(r, r->water_ripple, p[TM_VILLAGE_POINTER_WATER_RIPPLE],
                             (size_t)n[TM_VILLAGE_INT_WATER_RIPPLE_FLOATS] * 4);
    r->ripple_made = n[TM_VILLAGE_INT_WATER_RIPPLE_MADE];
  }
  if (n[TM_VILLAGE_INT_WATER_BED_MADE] != r->bed_made || !r->water_pebble) {
    r->water_pebble = upload(r, r->water_pebble, p[TM_VILLAGE_POINTER_WATER_PEBBLE],
                             (size_t)n[TM_VILLAGE_INT_WATER_PEBBLE_FLOATS] * 4);
    r->bed_made = n[TM_VILLAGE_INT_WATER_BED_MADE];
  }
  r->water_words = upload(r, r->water_words, p[TM_VILLAGE_POINTER_WATER_WORDS],
                          (size_t)n[TM_VILLAGE_INT_WATER_WORDS] * 4);
  size_t samples = (size_t)(n[TM_VILLAGE_INT_WATER_GRID_WIDTH] * n[TM_VILLAGE_INT_WATER_GRID_HEIGHT]) * 12;
  r->water_samples = room(r, r->water_samples, samples);
}

int village_metal_draw(VillageMetal *metal) {
  @autoreleasepool {
    VillageRenderer *r = renderer(metal);
    const int64_t *n = r->api.ints(r->app);
    const float *f = r->api.floats(r->app);
    const int64_t *p = r->api.pointers(r->app);
    int width = (int)n[TM_VILLAGE_INT_WIDTH];
    int height = (int)n[TM_VILLAGE_INT_HEIGHT];
    if (width < 1 || height < 1) return 1;
    if (width != r->width || height != r->height) make_targets(r, width, height);

    int64_t triangles = n[TM_VILLAGE_INT_TRIANGLES];
    r->vertices = upload(r, r->vertices, p[TM_VILLAGE_POINTER_VERTICES],
                         (size_t)n[TM_VILLAGE_INT_VERTICES] * VERTEX_BYTES);
    r->corners = upload(r, r->corners, p[TM_VILLAGE_POINTER_CORNERS], (size_t)triangles * CORNER_BYTES);
    r->codes = upload(r, r->codes, p[TM_VILLAGE_POINTER_CODES], (size_t)triangles * CODE_BYTES);
    r->grid = upload(r, r->grid, p[TM_VILLAGE_POINTER_SKY],
                     (size_t)(n[TM_VILLAGE_INT_SKY_COLUMNS] * n[TM_VILLAGE_INT_SKY_ROWS]) * SKY_SAMPLE_BYTES);
    load_shadow(r, n[TM_VILLAGE_INT_STILL_ON], n[TM_VILLAGE_INT_STILL_MADE], n[TM_VILLAGE_INT_STILL_STRIDE],
                p[TM_VILLAGE_POINTER_STILL_DEPTH], &r->still, &r->still_made);
    load_shadow(r, n[TM_VILLAGE_INT_MOVING_ON], n[TM_VILLAGE_INT_MOVING_MADE], n[TM_VILLAGE_INT_MOVING_STRIDE],
                p[TM_VILLAGE_POINTER_MOVING_DEPTH], &r->moving, &r->moving_made);
    load_maps(r, n, p);
    load_post(r, n, p);
    VillagePost post;
    fill_post(&post, n, f);

    VillageFrame frame;
    memset(&frame, 0, sizeof frame);
    memcpy(frame.still_clip, (const void *)(intptr_t)p[TM_VILLAGE_POINTER_STILL_CLIP], sizeof frame.still_clip);
    memcpy(frame.moving_clip, (const void *)(intptr_t)p[TM_VILLAGE_POINTER_MOVING_CLIP],
           sizeof frame.moving_clip);
    frame.fog_color[0] = f[TM_VILLAGE_FLOAT_FOG_RED];
    frame.fog_color[1] = f[TM_VILLAGE_FLOAT_FOG_GREEN];
    frame.fog_color[2] = f[TM_VILLAGE_FLOAT_FOG_BLUE];
    frame.exposure = f[TM_VILLAGE_FLOAT_EXPOSURE];
    frame.bias = f[TM_VILLAGE_FLOAT_BIAS];
    frame.still_per_meter = f[TM_VILLAGE_FLOAT_STILL_PER_METER];
    frame.moving_per_meter = f[TM_VILLAGE_FLOAT_MOVING_PER_METER];
    frame.width = width;
    frame.height = height;
    frame.fog = (int32_t)n[TM_VILLAGE_INT_FOG];
    frame.still_on = (int32_t)n[TM_VILLAGE_INT_STILL_ON];
    frame.still_size = (int32_t)n[TM_VILLAGE_INT_STILL_SIZE];
    frame.still_stride = (int32_t)n[TM_VILLAGE_INT_STILL_STRIDE];
    frame.moving_on = (int32_t)n[TM_VILLAGE_INT_MOVING_ON];
    frame.moving_size = (int32_t)n[TM_VILLAGE_INT_MOVING_SIZE];
    frame.moving_stride = (int32_t)n[TM_VILLAGE_INT_MOVING_STRIDE];
    frame.sky_columns = (int32_t)n[TM_VILLAGE_INT_SKY_COLUMNS];
    frame.sky_rows = (int32_t)n[TM_VILLAGE_INT_SKY_ROWS];
    frame.sky_step = (int32_t)n[TM_VILLAGE_INT_SKY_STEP];

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    /* The sky covers every pixel, so the images need no clear. */
    pass.colorAttachments[0].texture = r->color;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[1].texture = r->depth_out;
    pass.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[1].storeAction = MTLStoreActionStore;
    pass.depthAttachment.texture = r->depth_test;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.clearDepth = 1.0;
    pass.depthAttachment.storeAction = MTLStoreActionDontCare;

    id<MTLCommandBuffer> commands = [r->queue commandBuffer];
    id<MTLRenderCommandEncoder> draw = [commands renderCommandEncoderWithDescriptor:pass];
    [draw setRenderPipelineState:r->sky];
    [draw setDepthStencilState:r->behind];
    [draw setFragmentBytes:&frame length:sizeof frame atIndex:0];
    [draw setFragmentBuffer:r->grid offset:0 atIndex:1];
    [draw setFragmentBytes:&post length:sizeof post atIndex:2];
    [draw setFragmentBuffer:r->cover offset:0 atIndex:3];
    [draw drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    if (triangles > 0) {
      [draw setRenderPipelineState:r->scene];
      [draw setDepthStencilState:r->nearer];
      [draw setVertexBuffer:r->vertices offset:0 atIndex:0];
      [draw setFragmentBytes:&frame length:sizeof frame atIndex:0];
      [draw setFragmentBuffer:r->codes offset:0 atIndex:1];
      [draw setFragmentBuffer:r->still offset:0 atIndex:2];
      [draw setFragmentBuffer:r->moving offset:0 atIndex:3];
      [draw setFragmentBuffer:r->texels offset:0 atIndex:4];
      [draw setFragmentBuffer:r->starts offset:0 atIndex:5];
      [draw setFragmentBuffer:r->widths offset:0 atIndex:6];
      [draw setFragmentBuffer:r->heights offset:0 atIndex:7];
      [draw setFragmentBuffer:r->firsts offset:0 atIndex:8];
      [draw setFragmentBuffer:r->counts offset:0 atIndex:9];
      [draw setFragmentBuffer:r->wraps_s offset:0 atIndex:10];
      [draw setFragmentBuffer:r->wraps_t offset:0 atIndex:11];
      [draw drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                       indexCount:(NSUInteger)triangles * 3
                        indexType:MTLIndexTypeUInt32
                      indexBuffer:r->corners
                indexBufferOffset:0];
    }
    [draw endEncoding];

    /* The passes after the triangles. The water is shaded on its grid, and then
     * composed over the triangles; the edges are smoothed last. */
    id<MTLTexture> shown = r->color;
    if (n[TM_VILLAGE_INT_PASSES]) {
      MTLSize group = MTLSizeMake(8, 8, 1);
      id<MTLComputeCommandEncoder> compute = [commands computeCommandEncoder];
      if (n[TM_VILLAGE_INT_WATER_ON]) {
        [compute setComputePipelineState:r->water_grid];
        [compute setBytes:&frame length:sizeof frame atIndex:0];
        [compute setBytes:&post length:sizeof post atIndex:1];
        [compute setBuffer:r->water_surface offset:0 atIndex:2];
        [compute setBuffer:r->water_ripple offset:0 atIndex:3];
        [compute setBuffer:r->water_caustic offset:0 atIndex:4];
        [compute setBuffer:r->water_pebble offset:0 atIndex:5];
        [compute setBuffer:r->water_words offset:0 atIndex:6];
        [compute setBuffer:r->water_samples offset:0 atIndex:7];
        [compute dispatchThreads:MTLSizeMake((NSUInteger)n[TM_VILLAGE_INT_WATER_GRID_WIDTH],
                                             (NSUInteger)n[TM_VILLAGE_INT_WATER_GRID_HEIGHT], 1)
           threadsPerThreadgroup:group];
        [compute setComputePipelineState:r->water_compose];
        [compute setBytes:&frame length:sizeof frame atIndex:0];
        [compute setBytes:&post length:sizeof post atIndex:1];
        [compute setBuffer:r->water_words offset:0 atIndex:2];
        [compute setBuffer:r->water_samples offset:0 atIndex:3];
        [compute setTexture:r->depth_out atIndex:0];
        [compute setTexture:r->color atIndex:1];
        [compute dispatchThreads:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
           threadsPerThreadgroup:group];
      }
      if (n[TM_VILLAGE_INT_SMOOTH_ON]) {
        [compute setComputePipelineState:r->smooth];
        [compute setBytes:&frame length:sizeof frame atIndex:0];
        [compute setTexture:r->color atIndex:0];
        [compute setTexture:r->smoothed atIndex:1];
        [compute dispatchThreads:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
           threadsPerThreadgroup:group];
        shown = r->smoothed;
      }
      [compute endEncoding];
    }

    id<MTLBlitCommandEncoder> copy = [commands blitCommandEncoder];
    MTLSize extent = MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1);
    [copy copyFromTexture:shown
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:extent
                 toBuffer:r->color_out
        destinationOffset:0
   destinationBytesPerRow:(NSUInteger)width * 4
 destinationBytesPerImage:(NSUInteger)width * height * 4];
    if (n[TM_VILLAGE_INT_DEPTH]) {
      [copy copyFromTexture:r->depth_out
                sourceSlice:0
                sourceLevel:0
               sourceOrigin:MTLOriginMake(0, 0, 0)
                 sourceSize:extent
                   toBuffer:r->depth_read
          destinationOffset:0
     destinationBytesPerRow:(NSUInteger)width * 4
   destinationBytesPerImage:(NSUInteger)width * height * 4];
    }
    [copy endEncoding];
    [commands commit];
    [commands waitUntilCompleted];
    if (commands.status != MTLCommandBufferStatusCompleted) {
      if (!r->failed) {
        fprintf(stderr, "threemojo_host: the GPU did not finish a frame: %s\n",
                commands.error.localizedDescription.UTF8String);
      }
      r->failed = true;
      return 1;
    }
    r->gpu_ns += (uint64_t)((commands.GPUEndTime - commands.GPUStartTime) * 1e9);

    size_t bytes = (size_t)width * height * 4;
    memcpy((void *)(intptr_t)p[TM_VILLAGE_POINTER_COLOR], r->color_out.contents, bytes);
    if (n[TM_VILLAGE_INT_DEPTH]) {
      memcpy((void *)(intptr_t)p[TM_VILLAGE_POINTER_DEPTH], r->depth_read.contents, bytes);
    }
    return 0;
  }
}
