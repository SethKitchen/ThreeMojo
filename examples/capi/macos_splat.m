/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * The splat library on Metal. See macos_splat.h, and splat.metal for the
 * shaders. build.sh turns splat.metal into splat_msl.h, a C string, and the
 * shaders compile when the window opens, so no Metal toolchain is needed to
 * build the host.
 *
 * Three frames can be on the GPU at once. Each has its own copy of the draw
 * order, because the CPU writes the order while an earlier frame still reads
 * its own. Everything else is made once or made again when it changes, and
 * Metal keeps a buffer alive until the frames that use it are done.
 */
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

#include "macos_splat.h"
#include "splat_msl.h"

#define FRAMES_IN_FLIGHT 3
#define GROUP 64
#define PROJECTED_BYTES_A_SPLAT 48
#define VIEW_BYTES (TM_SPLAT_VIEW_FLOATS * 4)

/* Where each pass finds each buffer. They are the indexes in splat.metal. */
enum {
  PROJECT_VIEW = 0,
  PROJECT_CENTERS = 1,
  PROJECT_COVARIANCES = 2,
  PROJECT_COLORS = 3,
  PROJECT_SH1 = 4,
  PROJECT_SH2 = 5,
  PROJECT_SH3 = 6,
  PROJECT_ORDER = 7,
  PROJECT_PROJECTED = 8,
  DRAW_VIEW = 0,
  DRAW_PROJECTED = 1
};

@interface SplatRenderer : NSObject {
@public
  SplatApi api;
  tm_app *app;
  CAMetalLayer *layer; /* nil: the frame goes to `shown`, and can be read back */
  id<MTLDevice> device;
  id<MTLCommandQueue> queue;
  id<MTLComputePipelineState> project;
  id<MTLRenderPipelineState> draw;
  id<MTLRenderPipelineState> resolve;
  id<MTLTexture> picture; /* the blended frame, half floats */
  id<MTLTexture> shown;   /* the frame as 8-bit RGBA, when there is no layer */
  id<MTLBuffer> centers, covariances, colors, sh1, sh2, sh3, projected;
  id<MTLBuffer> order[FRAMES_IN_FLIGHT];
  int64_t order_made[FRAMES_IN_FLIGHT]; /* which sort each copy of the order holds */
  dispatch_semaphore_t slots;
  _Atomic uint64_t gpu_ns;
  int width, height;
  int count;       /* splats on the GPU */
  int64_t scan;    /* which scan is on the GPU: 0 for none */
  uint64_t frame;  /* frames drawn, to pick a copy of the order */
  float view[TM_SPLAT_VIEW_FLOATS];
  NSData *pixels; /* the last read-back frame */
}
@end

@implementation SplatRenderer
@end

static void fail(char *error, size_t size, NSString *reason) {
  if (error && size > 0) snprintf(error, size, "%s", reason.UTF8String);
}

static id<MTLBuffer> make_buffer(SplatRenderer *r, const void *bytes, size_t length) {
  /* A band that the scan lacks has no bytes, and its shader code never runs. */
  if (length == 0) return [r->device newBufferWithLength:16 options:MTLResourceStorageModeShared];
  return [r->device newBufferWithBytes:bytes length:length options:MTLResourceStorageModeShared];
}

static void make_pictures(SplatRenderer *r) {
  MTLTextureDescriptor *half =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                         width:(NSUInteger)r->width
                                                        height:(NSUInteger)r->height
                                                     mipmapped:NO];
  half.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  half.storageMode = MTLStorageModePrivate;
  r->picture = [r->device newTextureWithDescriptor:half];
  if (!r->layer) {
    MTLTextureDescriptor *bytes =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:(NSUInteger)r->width
                                                          height:(NSUInteger)r->height
                                                       mipmapped:NO];
    bytes.usage = MTLTextureUsageRenderTarget;
    bytes.storageMode = MTLStorageModeShared;
    r->shown = [r->device newTextureWithDescriptor:bytes];
  }
}

static const float *words(SplatRenderer *r, int32_t part, int32_t *count) {
  *count = r->api.words(r->app, part);
  return *count > 0 ? (const float *)r->api.part(r->app, part) : NULL;
}

/* Put a new scan on the GPU: its arrays, and room for what the passes make. */
static void load_scan(SplatRenderer *r) {
  int32_t size;
  const void *data;
  data = words(r, TM_SPLAT_CENTERS, &size);
  r->centers = make_buffer(r, data, (size_t)size * 4);
  data = words(r, TM_SPLAT_COVARIANCES, &size);
  r->covariances = make_buffer(r, data, (size_t)size * 4);
  data = words(r, TM_SPLAT_COLORS, &size);
  r->colors = make_buffer(r, data, (size_t)size * 4);
  data = words(r, TM_SPLAT_SH1, &size);
  r->sh1 = make_buffer(r, data, (size_t)size * 4);
  data = words(r, TM_SPLAT_SH2, &size);
  r->sh2 = make_buffer(r, data, (size_t)size * 4);
  data = words(r, TM_SPLAT_SH3, &size);
  r->sh3 = make_buffer(r, data, (size_t)size * 4);
  r->count = r->api.info(r->app, TM_SPLAT_INFO_COUNT);
  r->projected = [r->device newBufferWithLength:(NSUInteger)r->count * PROJECTED_BYTES_A_SPLAT
                                        options:MTLResourceStorageModePrivate];
  for (int slot = 0; slot < FRAMES_IN_FLIGHT; slot++) {
    r->order[slot] = [r->device newBufferWithLength:(NSUInteger)r->count * 4
                                            options:MTLResourceStorageModeShared];
    r->order_made[slot] = 0;
  }
  r->scan = r->api.info(r->app, TM_SPLAT_INFO_SCAN);
}

SplatMetal *splat_metal_create(const SplatApi *api, tm_app *app, void *layer, int width,
                               int height, char *error, size_t error_size) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      fail(error, error_size, @"this Mac has no Metal device");
      return NULL;
    }
    SplatRenderer *r = [SplatRenderer new];
    r->api = *api;
    r->app = app;
    r->device = device;
    r->layer = (__bridge CAMetalLayer *)layer;
    r->width = width;
    r->height = height;
    r->queue = [device newCommandQueue];
    r->slots = dispatch_semaphore_create(FRAMES_IN_FLIGHT);

    MTLCompileOptions *options = [MTLCompileOptions new];
    /* Exact sqrt, exp and atan2, as the CPU rounds them. */
    if (@available(macOS 15.0, *)) options.mathMode = MTLMathModeSafe;
    else options.fastMathEnabled = NO;
    NSError *failure = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:@(SPLAT_MSL)
                                                  options:options
                                                    error:&failure];
    if (!library) {
      fail(error, error_size, [@"splat.metal does not compile: "
                                  stringByAppendingString:failure.localizedDescription]);
      return NULL;
    }
    r->project = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"project"]
                                                       error:&failure];
    if (!r->project) {
      fail(error, error_size, failure.localizedDescription);
      return NULL;
    }

    MTLRenderPipelineDescriptor *blend = [MTLRenderPipelineDescriptor new];
    blend.vertexFunction = [library newFunctionWithName:@"splat_vertex"];
    blend.fragmentFunction = [library newFunctionWithName:@"splat_fragment"];
    MTLRenderPipelineColorAttachmentDescriptor *color = blend.colorAttachments[0];
    color.pixelFormat = MTLPixelFormatRGBA16Float;
    /* Source-over with straight alpha, which keeps the picture opaque. */
    color.blendingEnabled = YES;
    color.rgbBlendOperation = MTLBlendOperationAdd;
    color.alphaBlendOperation = MTLBlendOperationAdd;
    color.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    color.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    color.sourceAlphaBlendFactor = MTLBlendFactorZero;
    color.destinationAlphaBlendFactor = MTLBlendFactorOne;
    r->draw = [device newRenderPipelineStateWithDescriptor:blend error:&failure];
    if (!r->draw) {
      fail(error, error_size, failure.localizedDescription);
      return NULL;
    }

    MTLRenderPipelineDescriptor *show = [MTLRenderPipelineDescriptor new];
    show.vertexFunction = [library newFunctionWithName:@"resolve_vertex"];
    show.fragmentFunction = [library newFunctionWithName:@"resolve_fragment"];
    show.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (layer) {
      r->layer.device = device;
      r->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
      r->layer.framebufferOnly = YES;
      r->layer.maximumDrawableCount = FRAMES_IN_FLIGHT;
      r->layer.drawableSize = CGSizeMake(width, height);
      /* The frame is in sRGB, as the CPU path tells the window. */
      CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      r->layer.colorspace = space;
      CGColorSpaceRelease(space);
    } else {
      show.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    }
    r->resolve = [device newRenderPipelineStateWithDescriptor:show error:&failure];
    if (!r->resolve) {
      fail(error, error_size, failure.localizedDescription);
      return NULL;
    }
    make_pictures(r);
    return (SplatMetal *)CFBridgingRetain(r);
  }
}

static SplatRenderer *renderer(const SplatMetal *metal) {
  return (__bridge SplatRenderer *)(const void *)metal;
}

void splat_metal_destroy(SplatMetal *metal) {
  if (!metal) return;
  SplatRenderer *r = renderer(metal);
  /* Take every slot: the frames on the GPU are done when all three are ours.
   * A semaphore must hold its first count when it is freed, so give them back. */
  for (int slot = 0; slot < FRAMES_IN_FLIGHT; slot++) {
    dispatch_semaphore_wait(r->slots, DISPATCH_TIME_FOREVER);
  }
  for (int slot = 0; slot < FRAMES_IN_FLIGHT; slot++) dispatch_semaphore_signal(r->slots);
  CFRelease(metal);
}

const char *splat_metal_name(const SplatMetal *metal) {
  return renderer(metal)->device.name.UTF8String;
}

void splat_metal_resize(SplatMetal *metal, int width, int height) {
  SplatRenderer *r = renderer(metal);
  if (width == r->width && height == r->height) return;
  r->width = width;
  r->height = height;
  /* Frames on the GPU keep the old pictures alive until they are done. */
  make_pictures(r);
}

uint64_t splat_metal_gpu_ns(const SplatMetal *metal) {
  return atomic_load(&renderer(metal)->gpu_ns);
}

int splat_metal_draw(SplatMetal *metal, int32_t ready) {
  @autoreleasepool {
    SplatRenderer *r = renderer(metal);
    dispatch_semaphore_wait(r->slots, DISPATCH_TIME_FOREVER);
    id<CAMetalDrawable> drawable = nil;
    id<MTLTexture> target = r->shown;
    if (r->layer) {
      drawable = [r->layer nextDrawable];
      /* The window changed size since the app did. The next frame fits. */
      if (!drawable || (int)drawable.texture.width != r->width ||
          (int)drawable.texture.height != r->height) {
        dispatch_semaphore_signal(r->slots);
        return 1;
      }
      target = drawable.texture;
    }
    int slot = (int)(r->frame++ % FRAMES_IN_FLIGHT);
    float background[3] = {7.0f / 255.0f, 8.0f / 255.0f, 15.0f / 255.0f};
    if (ready == 0) {
      if (r->api.info(r->app, TM_SPLAT_INFO_SCAN) != r->scan) load_scan(r);
      int64_t sorted = r->api.info(r->app, TM_SPLAT_INFO_ORDER);
      if (sorted != r->order_made[slot]) {
        int32_t size;
        const void *order = words(r, TM_SPLAT_ORDER, &size);
        /* A missed copy must stay stale, so the next frame tries again. */
        if (order && (size_t)size * 4 == (size_t)r->order[slot].length) {
          memcpy(r->order[slot].contents, order, (size_t)size * 4);
          r->order_made[slot] = sorted;
        }
      }
      int32_t size;
      const float *view = words(r, TM_SPLAT_VIEW, &size);
      if (view && size == TM_SPLAT_VIEW_FLOATS) {
        memcpy(r->view, view, VIEW_BYTES);
      }
      memcpy(background, r->view + TM_SPLAT_VIEW_BACKGROUND, sizeof background);
    }

    id<MTLCommandBuffer> commands = [r->queue commandBuffer];
    if (ready == 0) {
      id<MTLComputeCommandEncoder> compute = [commands computeCommandEncoder];
      [compute setComputePipelineState:r->project];
      [compute setBytes:r->view length:VIEW_BYTES atIndex:PROJECT_VIEW];
      [compute setBuffer:r->centers offset:0 atIndex:PROJECT_CENTERS];
      [compute setBuffer:r->covariances offset:0 atIndex:PROJECT_COVARIANCES];
      [compute setBuffer:r->colors offset:0 atIndex:PROJECT_COLORS];
      [compute setBuffer:r->sh1 offset:0 atIndex:PROJECT_SH1];
      [compute setBuffer:r->sh2 offset:0 atIndex:PROJECT_SH2];
      [compute setBuffer:r->sh3 offset:0 atIndex:PROJECT_SH3];
      [compute setBuffer:r->order[slot] offset:0 atIndex:PROJECT_ORDER];
      [compute setBuffer:r->projected offset:0 atIndex:PROJECT_PROJECTED];
      [compute dispatchThreadgroups:MTLSizeMake(((NSUInteger)r->count + GROUP - 1) / GROUP, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(GROUP, 1, 1)];
      [compute endEncoding];
    }

    MTLRenderPassDescriptor *first = [MTLRenderPassDescriptor renderPassDescriptor];
    first.colorAttachments[0].texture = r->picture;
    first.colorAttachments[0].loadAction = MTLLoadActionClear;
    first.colorAttachments[0].storeAction = MTLStoreActionStore;
    first.colorAttachments[0].clearColor =
        MTLClearColorMake(background[0], background[1], background[2], 1.0);
    id<MTLRenderCommandEncoder> blend = [commands renderCommandEncoderWithDescriptor:first];
    if (ready == 0) {
      [blend setRenderPipelineState:r->draw];
      [blend setVertexBytes:r->view length:VIEW_BYTES atIndex:DRAW_VIEW];
      [blend setVertexBuffer:r->projected offset:0 atIndex:DRAW_PROJECTED];
      [blend drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4
              instanceCount:(NSUInteger)r->count];
    }
    [blend endEncoding];

    MTLRenderPassDescriptor *last = [MTLRenderPassDescriptor renderPassDescriptor];
    last.colorAttachments[0].texture = target;
    last.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    last.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> show = [commands renderCommandEncoderWithDescriptor:last];
    [show setRenderPipelineState:r->resolve];
    [show setFragmentTexture:r->picture atIndex:0];
    [show drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [show endEncoding];

    if (drawable) [commands presentDrawable:drawable];
    [commands addCompletedHandler:^(id<MTLCommandBuffer> done) {
      atomic_fetch_add(&r->gpu_ns, (uint64_t)((done.GPUEndTime - done.GPUStartTime) * 1e9));
      dispatch_semaphore_signal(r->slots);
    }];
    [commands commit];
    return 0;
  }
}

const uint8_t *splat_metal_read(SplatMetal *metal) {
  SplatRenderer *r = renderer(metal);
  if (r->layer) return NULL;
  /* The frames on the GPU are done when all three slots are ours. */
  for (int slot = 0; slot < FRAMES_IN_FLIGHT; slot++) {
    dispatch_semaphore_wait(r->slots, DISPATCH_TIME_FOREVER);
  }
  NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)r->width * r->height * 4];
  [r->shown getBytes:bytes.mutableBytes
         bytesPerRow:(NSUInteger)r->width * 4
          fromRegion:MTLRegionMake2D(0, 0, (NSUInteger)r->width, (NSUInteger)r->height)
         mipmapLevel:0];
  for (int slot = 0; slot < FRAMES_IN_FLIGHT; slot++) dispatch_semaphore_signal(r->slots);
  r->pixels = bytes;
  return bytes.bytes;
}
