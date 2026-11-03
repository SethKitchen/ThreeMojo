/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * The village game's frame on Metal. window/capi_village.mojo prepares the
 * triangles on the CPU: it clips them, culls them, and lights their vertices.
 * These shaders do what renderers/game_renderer.mojo does after that, with the
 * GPU's raster in place of the CPU's tiles: they draw the sky, rasterize the
 * triangles with a depth test, and shade each pixel from its vertices, the sun's
 * shadow maps and the maps that are read at each pixel. Then they tone map the
 * light with ACES and encode it as sRGB.
 *
 * The arithmetic is the CPU resolve's, line for line (_resolve_task and its
 * helpers in game_renderer.mojo), so the two paths agree to within a byte.
 * build.sh turns this file into village_msl.h, a C string, and the shaders
 * compile when the window opens, so no Metal toolchain is needed to build the
 * host.
 */
#include <metal_stdlib>
using namespace metal;

/* What macos_village.m passes in. The layout is VillageFrame there. */
struct Frame {
  float4x4 still_clip;
  float4x4 moving_clip;
  float4 fog_color;
  float exposure;
  float bias;
  float still_per_meter;
  float moving_per_meter;
  int width;
  int height;
  int fog;
  int still_on;
  int still_size;
  int still_stride;
  int moving_on;
  int moving_size;
  int moving_stride;
  int sky_columns;
  int sky_rows;
  int sky_step;
};

constant float LEVEL_CODE = 32.0;

/* three.js's ACESFilmicToneMapping, as render/tonemap.mojo's aces_tone. */
static float3 aces_fit(float3 v) {
  float3 a = v * (v + 0.0245786) - 0.000090537;
  float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return a / b;
}

static float3 aces_tone(float3 c, float exposure) {
  float scale = exposure / 0.6;
  float3 s = c * scale;
  float3 i = float3(0.59719 * s.x + 0.35458 * s.y + 0.04823 * s.z,
                    0.07600 * s.x + 0.90834 * s.y + 0.01566 * s.z,
                    0.02840 * s.x + 0.13383 * s.y + 0.83777 * s.z);
  float3 f = aces_fit(i);
  float3 o = float3(1.60475 * f.x - 0.53108 * f.y - 0.07367 * f.z,
                    -0.10208 * f.x + 1.10813 * f.y - 0.00605 * f.z,
                    -0.00327 * f.x - 0.07276 * f.y + 1.07602 * f.z);
  return clamp(o, 0.0, 1.0);
}

/* The sRGB encoding, which the CPU rounds to a byte. The attachment rounds the
 * same way. */
static float3 srgb(float3 v) {
  float3 low = v * 12.92;
  float3 high = 1.055 * pow(v, float3(1.0 / 2.4)) - 0.055;
  return select(high, low, v <= 0.0031308);
}

static float3 shown(float3 light, float exposure) {
  return srgb(aces_tone(light, exposure));
}

/* The sky: the background sampled on a grid of `sky_step` pixels, and mixed from
 * the four samples round each pixel. */
static float3 sky_at(constant Frame &frame, device const float *grid, uint2 pixel) {
  int step = frame.sky_step;
  int column = min(int(pixel.x), frame.width - 1);
  int gx = column / step;
  int gy = int(pixel.y) / step;
  float fx = float(column - gx * step) / float(step);
  float fy = float(int(pixel.y) - gy * step) / float(step);
  int s00 = (gx + gy * frame.sky_columns) * 3;
  int s10 = s00 + 3;
  int s01 = s00 + frame.sky_columns * 3;
  int s11 = s01 + 3;
  float3 a = float3(grid[s00], grid[s00 + 1], grid[s00 + 2]);
  float3 b = float3(grid[s10], grid[s10 + 1], grid[s10 + 2]);
  float3 c = float3(grid[s01], grid[s01 + 1], grid[s01 + 2]);
  float3 d = float3(grid[s11], grid[s11 + 1], grid[s11 + 2]);
  float3 top = a + (b - a) * fx;
  float3 bottom = c + (d - c) * fx;
  return top + (bottom - top) * fy;
}

/* What the passes after the triangles need (VillagePost in macos_village.m):
 * the weather's clouds and the hour's night over the sky, the pond's water,
 * and the smoothing of edges. The library makes the numbers
 * (extensions/village/gpu_post.mojo); each is the CPU pass's own. */
struct Post {
  float4x4 water_clip;  /* the camera's projection and view */
  float4 water_eye;     /* xyz: the camera's place */
  float4 water_night;   /* xyz: the color that water turns toward, in bytes; w: its own light's share */
  float4 cover_gray;    /* xyz: a cloud's face, in bytes; w: the veil */
  float4 cover_fog;     /* xyz: the mist, in bytes; w: how much it takes */
  float4 cover_misc;    /* x: the lightning's gain; y: the clouds' gloom */
  float4 night_a;       /* x: daylight; y: dusk; z: the stars; w: the star lattice */
  float4 night_d00;     /* xyz: the direction through the top left corner; w: the stars' rate */
  float4 night_across;
  float4 night_down;
  float4 night_glow;    /* xyz: the dusk's gain on the low sky */
  float4 night_sky;     /* xyz: the night sky, in bytes */
  int4 cover_ints;      /* the clouds' grid columns, rows and step, and 1 if it is night */
  int4 water_ints;      /* 1 if there is water, the step, the grid's width and height */
  int4 flags;           /* x: 1 if the passes are the GPU's; y: 1 if it smooths the edges */
};

/* Zero below edge0, one above edge1, and Hermite's curve between (smoothstep
 * in math/smoothstep.mojo, which leaves equal edges a hard step). */
static float hermite(float edge0, float edge1, float x) {
  if (x <= edge0) return 0.0;
  if (x >= edge1) return 1.0;
  float t = (x - edge0) / (edge1 - edge0);
  return t * t * (3.0 - 2.0 * t);
}

/* extensions/vegetation/noise.mojo, hash01. The arithmetic is 32 bits wide,
 * and wraps as the CPU's masked product does. */
static float hash01(int a, int b, int seed) {
  uint mixed = uint(a) * 374761393u + uint(b) * 668265263u + uint(seed) * 1442695041u;
  uint h = mixed;
  h = (h ^ (h >> 15)) * 0x2C1B3C6Du;
  h = (h ^ (h >> 12)) * 0x297A2D39u;
  h = h ^ (h >> 15);
  return float(h) / 4294967295.0;
}

/* Weather.cover: the clouds, the mist and the lightning over a sky pixel, in
 * bytes. The clouds' grid is the CPU's. */
static float3 weather_cover(constant Post &post, device const float *cover, uint2 pixel,
                            float3 sky) {
  int columns = post.cover_ints.x;
  int rows = post.cover_ints.y;
  float step = float(post.cover_ints.z);
  float gy = float(pixel.y) / step;
  int r0 = min(int(gy), rows - 2);
  float ty = gy - float(r0);
  float gx = float(pixel.x) / step;
  int c0 = min(int(gx), columns - 2);
  float tx = gx - float(c0);
  float a = cover[r0 * columns + c0];
  float b = cover[r0 * columns + c0 + 1];
  float c = cover[(r0 + 1) * columns + c0];
  float e = cover[(r0 + 1) * columns + c0 + 1];
  float top = a + (b - a) * tx;
  float bottom = c + (e - c) * tx;
  float cloud = top + (bottom - top) * ty;
  float veil = post.cover_gray.w;
  float alpha = min(1.0, veil + cloud * (1.0 - veil));
  /* The underside of a thick cloud is darker than its edge. */
  float3 tone = post.cover_gray.xyz * (1.0 - 0.18 * cloud * post.cover_misc.y);
  float3 seen = sky + (tone - sky) * alpha;
  seen = seen + (post.cover_fog.xyz - seen) * post.cover_fog.w;
  seen = seen * post.cover_misc.x;
  return floor(min(float3(255.0), seen));
}

/* DayCycle.night_sky: the night, the dusk's glow and the stars over a sky
 * pixel, in bytes. */
static float3 night_sky(constant Post &post, int width, int height, uint2 pixel, float3 sky) {
  float day = post.night_a.x;
  float dusk = post.night_a.y;
  float stars = post.night_a.z;
  float grid = post.night_a.w;
  float fy = float(pixel.y) / float(height);
  float3 d = post.night_d00.xyz + post.night_across.xyz * (float(pixel.x) / float(width)) +
             post.night_down.xyz * fy;
  d = d / sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
  /* Low in the sky, the dusk's glow; and night over all. */
  float low = 1.0 - hermite(0.0, 0.35, d.y);
  float3 c = sky * (float3(1.0) + (post.night_glow.xyz - float3(1.0)) * (dusk * low));
  c = c + (post.night_sky.xyz - c) * (1.0 - day);
  float cell = hash01(int(floor(d.x * grid)), int(floor(d.z * grid)) * 977 + int(floor(d.y * grid)), 83);
  if (cell < post.night_d00.w) {
    /* A star fades into the haze near the horizon. */
    float bright = 120.0 + 135.0 * hash01(int(cell * 1.0e7), 1, 84);
    float seen = stars * hermite(0.03, 0.12, d.y);
    c = c + (float3(bright, bright, bright * 0.95) - c) * seen;
  }
  return floor(min(float3(255.0), c));
}

struct PixelOut {
  float4 color [[color(0)]];
  float depth [[color(1)]];
};

vertex float4 sky_vertex(uint vid [[vertex_id]]) {
  float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));
  return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

fragment PixelOut sky_fragment(float4 position [[position]], constant Frame &frame [[buffer(0)]],
                               device const float *grid [[buffer(1)]],
                               constant Post &post [[buffer(2)]],
                               device const float *cover [[buffer(3)]]) {
  PixelOut out;
  uint2 pixel = uint2(position.xy);
  float3 light = sky_at(frame, grid, pixel);
  float3 rgb = shown(light, frame.exposure);
  if (post.flags.x != 0) {
    /* The CPU does these on the sky's bytes. */
    float3 bytes = floor(rgb * 255.0 + 0.5);
    bytes = weather_cover(post, cover, pixel, bytes);
    if (post.cover_ints.w != 0) bytes = night_sky(post, frame.width, frame.height, pixel, bytes);
    rgb = bytes / 255.0;
  }
  out.color = float4(rgb, 1.0);
  out.depth = INFINITY;
  return out;
}

/* A vertex is 16 floats: the clip position, the ambient light, the sun's light,
 * the world position, a packed fog share, and the texture coordinates. */
struct VertexOut {
  float4 position [[position]];
  float3 ambient;
  float3 sun;
  float3 world;
  float packed;
  float2 uv;
};

vertex VertexOut scene_vertex(uint vid [[vertex_id]], device const float *vertices [[buffer(0)]]) {
  device const float *v = vertices + ulong(vid) * 16;
  VertexOut out;
  /* The CPU's clip space has z from -w to w. Metal's has it from 0 to w. */
  out.position = float4(v[0], v[1], (v[2] + v[3]) * 0.5, v[3]);
  out.ambient = float3(v[4], v[5], v[6]);
  out.sun = float3(v[7], v[8], v[9]);
  out.world = float3(v[10], v[11], v[12]);
  out.packed = v[13];
  out.uv = float2(v[14], v[15]);
  return out;
}

/* How much of the sun reaches a point, by a 2 by 2 comparison of one depth map:
 * 1 in full sun, 0 in full shadow, and 1 outside the map (_sun_shadows). */
static float texel_lit(device const float *texels, int x, int y, int last, int stride, float reach) {
  bool valid = x >= 0 && x <= last && y >= 0 && y <= last;
  if (!valid) return 1.0;
  return texels[y * stride + x] < reach ? 0.0 : 1.0;
}

static float sun_shadows(float4x4 clip, device const float *texels, int size, int stride,
                         float per_meter, float bias, float3 world) {
  float4 c = clip * float4(world, 1.0);
  bool on = c.x > -1.0 && c.x < 1.0 && c.y > -1.0 && c.y < 1.0;
  if (!on) return 1.0;
  float s = float(size);
  float tx = (c.x * 0.5 + 0.5) * s - 0.5;
  float ty = (0.5 - c.y * 0.5) * s - 0.5;
  float x0f = floor(tx);
  float y0f = floor(ty);
  float fx = tx - x0f;
  float fy = ty - y0f;
  int x0 = int(x0f);
  int y0 = int(y0f);
  float reach = c.z - bias * per_meter;
  int last = size - 1;
  float l00 = texel_lit(texels, x0, y0, last, stride, reach);
  float l10 = texel_lit(texels, x0 + 1, y0, last, stride, reach);
  float l01 = texel_lit(texels, x0, y0 + 1, last, stride, reach);
  float l11 = texel_lit(texels, x0 + 1, y0 + 1, last, stride, reach);
  float top = l00 + (l10 - l00) * fx;
  float bottom = l01 + (l11 - l01) * fx;
  return top + (bottom - top) * fy;
}

/* The texel index along one side of `size` texels, as render.texture.wrap_index
 * gives it: 0 repeats, 1 holds at the edge, 2 mirrors. */
static int wrap_texel(float x, float size, int mode) {
  float index;
  if (mode == 0) {
    index = x - size * floor(x / size);
  } else if (mode == 2) {
    float folded = x - 2.0 * size * floor(x / (2.0 * size));
    index = folded >= size ? 2.0 * size - 1.0 - folded : folded;
  } else {
    index = min(max(x, 0.0), size - 1.0);
  }
  return int(index);
}

struct Maps {
  device const float *texels;
  device const int *starts;
  device const int *widths;
  device const int *heights;
  device const int *firsts;
  device const int *counts;
  device const int *wraps_s;
  device const int *wraps_t;
};

static float3 texel_at(device const float *texels, int at) {
  return float3(texels[at], texels[at + 1], texels[at + 2]);
}

/* A map's color at texture coordinates, bilinear within the level that the
 * triangle's code names (_pixel_texel). */
static float3 pixel_texel(Maps maps, float code, float2 uv) {
  float slot_f = floor(code / LEVEL_CODE);
  int slot = int(slot_f);
  int wanted = int(code - slot_f * LEVEL_CODE + 0.5);
  int level = min(wanted, maps.counts[slot] - 1);
  int entry = maps.firsts[slot] + level;
  int w = maps.widths[entry];
  int h = maps.heights[entry];
  int start = maps.starts[entry];
  float wf = float(w);
  float hf = float(h);
  /* v counts up from the bottom row, as Texture.sample reads it. */
  float tx = uv.x * wf - 0.5;
  float ty = uv.y * hf - 0.5;
  float x0f = floor(tx);
  float y0f = floor(ty);
  float fx = tx - x0f;
  float fy = ty - y0f;
  int s = maps.wraps_s[slot];
  int t = maps.wraps_t[slot];
  int xs = wrap_texel(x0f, wf, s);
  int xs1 = wrap_texel(x0f + 1.0, wf, s);
  int ys = wrap_texel(y0f, hf, t);
  int ys1 = wrap_texel(y0f + 1.0, hf, t);
  int row0 = ys * w;
  int row1 = ys1 * w;
  float3 a = texel_at(maps.texels, start + (row0 + xs) * 3);
  float3 b = texel_at(maps.texels, start + (row0 + xs1) * 3);
  float3 c = texel_at(maps.texels, start + (row1 + xs) * 3);
  float3 d = texel_at(maps.texels, start + (row1 + xs1) * 3);
  float3 top = a + (b - a) * fx;
  float3 bottom = c + (d - c) * fx;
  return top + (bottom - top) * fy;
}

fragment PixelOut scene_fragment(VertexOut in [[stage_in]], uint primitive [[primitive_id]],
                                 constant Frame &frame [[buffer(0)]],
                                 device const float *codes [[buffer(1)]],
                                 device const float *still [[buffer(2)]],
                                 device const float *moving [[buffer(3)]],
                                 device const float *texels [[buffer(4)]],
                                 device const int *starts [[buffer(5)]],
                                 device const int *widths [[buffer(6)]],
                                 device const int *heights [[buffer(7)]],
                                 device const int *firsts [[buffer(8)]],
                                 device const int *counts [[buffer(9)]],
                                 device const int *wraps_s [[buffer(10)]],
                                 device const int *wraps_t [[buffer(11)]]) {
  float shadow = 1.0;
  /* A vertex's fog share is negative for a triangle that takes no shadow. */
  if (frame.still_on != 0 && in.packed >= 0.0) {
    shadow = sun_shadows(frame.still_clip, still, frame.still_size, frame.still_stride,
                         frame.still_per_meter, frame.bias, in.world);
    if (frame.moving_on != 0) {
      shadow = min(shadow, sun_shadows(frame.moving_clip, moving, frame.moving_size,
                                       frame.moving_stride, frame.moving_per_meter, frame.bias,
                                       in.world));
    }
  }
  float3 light = in.ambient + in.sun * shadow;
  float code = codes[primitive];
  if (code >= 0.0) {
    Maps maps = {texels, starts, widths, heights, firsts, counts, wraps_s, wraps_t};
    light *= pixel_texel(maps, code, in.uv);
    if (frame.fog != 0) {
      /* The fog's share kept, packed with the lookup. */
      float keep = in.packed >= 0.0 ? in.packed : -1.0 - in.packed;
      light = light * keep + frame.fog_color.xyz * (1.0 - keep);
    }
  }
  PixelOut out;
  out.color = float4(shown(light, frame.exposure), 1.0);
  /* The CPU keeps the NDC depth, from -1 to 1. */
  out.depth = in.position.z * 2.0 - 1.0;
  return out;
}

/* ------------------------------------------------------------------------
 * The pond's water. village_water.metal, which build.sh puts in front of this
 * file, shades one ray as examples/capi/web/water.wgsl does. These kernels do
 * what WaterScene.compose does round it, with the village's shade step (a
 * step of two or more: the water is tested where the still plane is):
 *
 *   water_grid     shades the grid of samples, one thread a sample;
 *   water_compose  tests each pixel against the triangles' depth, mixes its
 *                  color from the four samples round it, grades it, and
 *                  writes it over the pixel.
 */

/* The pixel of a grid sample. The samples are the pixels whose index is a
 * multiple of the step, and the last pixel (_grid_corners in frame.mojo). */
kernel void water_grid(constant Frame &frame [[buffer(0)]], constant Post &post [[buffer(1)]],
                       device const float *surface [[buffer(2)]],
                       device const float *ripple [[buffer(3)]],
                       device const float *caustic [[buffer(4)]],
                       device const float *pebble [[buffer(5)]],
                       constant uint *words [[buffer(6)]], device float *grid [[buffer(7)]],
                       uint2 id [[thread_position_in_grid]]) {
  int gw = post.water_ints.z;
  int gh = post.water_ints.w;
  if (int(id.x) >= gw || int(id.y) >= gh) return;
  int step = post.water_ints.y;
  int width = frame.width;
  int height = frame.height;
  int x = min(int(id.x) * step, width - 1);
  int y = min(int(id.y) * step, height - 1);
  Water ctx = {surface, ripple, caustic, pebble, words};
  float w = float(width);
  float h = float(height);
  float ndc_x = ((float(x) + 0.5) / w) * 2.0 - 1.0;
  float ndc_y = 1.0 - ((float(y) + 0.5) / h) * 2.0;
  float3 sun = float3(mf(ctx, 12u), mf(ctx, 13u), mf(ctx, 14u));
  float3 rgb = lit_radiance(ctx, camera_look(ctx), ndc_x, ndc_y, w / h, 2.0 / w, 2.0 / h, sun,
                            mf(ctx, 15u));
  uint at = (id.y * uint(gw) + id.x) * 3u;
  grid[at] = rgb.x;
  grid[at + 1] = rgb.y;
  grid[at + 2] = rgb.z;
}

kernel void water_compose(constant Frame &frame [[buffer(0)]], constant Post &post [[buffer(1)]],
                          constant uint *words [[buffer(2)]], device const float *grid [[buffer(3)]],
                          texture2d<float, access::read> depth_in [[texture(0)]],
                          texture2d<float, access::read_write> color [[texture(1)]],
                          uint2 id [[thread_position_in_grid]]) {
  int width = frame.width;
  int height = frame.height;
  if (int(id.x) >= width || int(id.y) >= height) return;
  Water ctx = {nullptr, nullptr, nullptr, nullptr, words};
  Look look = camera_look(ctx);
  float w = float(width);
  float h = float(height);
  float ndc_x = ((float(id.x) + 0.5) / w) * 2.0 - 1.0;
  float ndc_y = 1.0 - ((float(id.y) + 0.5) / h) * 2.0;
  float aspect = w / h;
  float3 rd = view_ray(ctx, look, ndc_x, ndc_y, aspect);
  if (rd.y > -0.0015) return;
  /* The still plane, where _depth_rows tests with a shade step above one. */
  float3 wd = unit(ctx, rd);
  float3 point = post.water_eye.xyz + wd * (-look.p.y / min(wd.y, -0.0015));
  float4 clip = post.water_clip * float4(point, 1.0);
  float inverse = clip.w != 0.0 ? 1.0 / clip.w : 1.0;
  float z = clip.z * inverse;
  if (!(z >= -1.0 && z <= 1.0)) return;
  if (z >= depth_in.read(id).x) return;
  /* The four samples round the pixel (_fill_task). */
  int step = post.water_ints.y;
  int gw = post.water_ints.z;
  int x0 = (int(id.x) / step) * step;
  int y0 = (int(id.y) / step) * step;
  int x1 = min(x0 + step, width - 1);
  int y1 = min(y0 + step, height - 1);
  float fx = 0.0;
  float fy = 0.0;
  if (x1 > x0) fx = float(int(id.x) - x0) / float(x1 - x0);
  if (y1 > y0) fy = float(int(id.y) - y0) / float(y1 - y0);
  int gx0 = x0 / step;
  int gy0 = y0 / step;
  int gx1 = x1 == width - 1 ? gw - 1 : gx0 + 1;
  int gy1 = y1 == height - 1 ? post.water_ints.w - 1 : gy0 + 1;
  float3 rgb;
  for (int ch = 0; ch < 3; ch++) {
    float a = grid[(gy0 * gw + gx0) * 3 + ch];
    float b = grid[(gy0 * gw + gx1) * 3 + ch];
    float d = grid[(gy1 * gw + gx0) * 3 + ch];
    float e = grid[(gy1 * gw + gx1) * 3 + ch];
    float top = a + (b - a) * fx;
    float bottom = d + (e - d) * fx;
    rgb[ch] = top + (bottom - top) * fy;
  }
  float3 graded = grade_pixel(ctx, rgb, float3(0.0), float3(0.0), id.x, id.y, uint(width),
                              uint(height), mf(ctx, 15u));
  float3 bytes = float3(to_byte(ctx, graded.x), to_byte(ctx, graded.y), to_byte(ctx, graded.z));
  float share = post.water_night.w;
  if (share < 1.0) {
    /* DayCycle's dim_water: the water mirrors the dark sky. */
    bytes = floor(bytes * (share * share) + post.water_night.xyz * (1.0 - share));
  }
  color.write(float4(bytes / 255.0, 1.0), id);
}

/* ------------------------------------------------------------------------
 * The smoothing of edges: render/game_smooth.mojo, smooth_edges, for one
 * pixel. The brightness is the luma of the bytes, and a sample is bilinear
 * between pixel centers.
 */
constant float EDGE_LEAST = 0.0833;
constant float EDGE_SHARE = 0.166;
constant float REDUCE_SHARE = 0.125;
constant float REDUCE_LEAST = 1.0 / 128.0;
constant float SPAN_MOST = 8.0;

static float3 pixel_bytes(texture2d<float, access::read> image, int x, int y, int width,
                          int height) {
  uint2 at = uint2(uint(min(max(x, 0), width - 1)), uint(min(max(y, 0), height - 1)));
  return rint(image.read(at).xyz * 255.0);
}

static float luma_of(float3 c) {
  return (c.x * 0.299 + c.y * 0.587 + c.z * 0.114) * (1.0 / 255.0);
}

static float3 sample_bytes(texture2d<float, access::read> image, float x, float y, int width,
                           int height) {
  float fx = x - 0.5;
  float fy = y - 0.5;
  float x0f = floor(fx);
  float y0f = floor(fy);
  float tx = fx - x0f;
  float ty = fy - y0f;
  int x0 = int(x0f);
  int y0 = int(y0f);
  float3 a = pixel_bytes(image, x0, y0, width, height);
  float3 b = pixel_bytes(image, x0 + 1, y0, width, height);
  float3 c = pixel_bytes(image, x0, y0 + 1, width, height);
  float3 d = pixel_bytes(image, x0 + 1, y0 + 1, width, height);
  float3 top = a + (b - a) * tx;
  float3 bottom = c + (d - c) * tx;
  return top + (bottom - top) * ty;
}

kernel void smooth_edges(constant Frame &frame [[buffer(0)]],
                         texture2d<float, access::read> source [[texture(0)]],
                         texture2d<float, access::write> target [[texture(1)]],
                         uint2 id [[thread_position_in_grid]]) {
  int width = frame.width;
  int height = frame.height;
  if (int(id.x) >= width || int(id.y) >= height) return;
  int x = int(id.x);
  int y = int(id.y);
  float3 middle_bytes = pixel_bytes(source, x, y, width, height);
  float nw = luma_of(pixel_bytes(source, x - 1, y - 1, width, height));
  float ne = luma_of(pixel_bytes(source, x + 1, y - 1, width, height));
  float sw = luma_of(pixel_bytes(source, x - 1, y + 1, width, height));
  float se = luma_of(pixel_bytes(source, x + 1, y + 1, width, height));
  float middle = luma_of(middle_bytes);
  float low = min(middle, min(min(nw, ne), min(sw, se)));
  float high = max(middle, max(max(nw, ne), max(sw, se)));
  if (!((high - low) >= max(EDGE_LEAST, high * EDGE_SHARE))) {
    target.write(float4(middle_bytes / 255.0, 1.0), id);
    return;
  }
  /* Across the larger change: the edge runs that way. */
  float dx = (sw + se) - (nw + ne);
  float dy = (nw + sw) - (ne + se);
  float reduce = max((nw + ne + sw + se) * (0.25 * REDUCE_SHARE), REDUCE_LEAST);
  float scale = 1.0 / (min(abs(dx), abs(dy)) + reduce);
  dx = max(-SPAN_MOST, min(SPAN_MOST, dx * scale));
  dy = max(-SPAN_MOST, min(SPAN_MOST, dy * scale));
  float cx = float(x) + 0.5;
  float cy = float(y) + 0.5;
  float3 n0 = sample_bytes(source, cx - dx * (1.0 / 6.0), cy - dy * (1.0 / 6.0), width, height);
  float3 n1 = sample_bytes(source, cx + dx * (1.0 / 6.0), cy + dy * (1.0 / 6.0), width, height);
  float3 f0 = sample_bytes(source, cx - dx * 0.5, cy - dy * 0.5, width, height);
  float3 f1 = sample_bytes(source, cx + dx * 0.5, cy + dy * 0.5, width, height);
  float3 near = (n0 + n1) * 0.5;
  float3 far = near * 0.5 + (f0 + f1) * 0.25;
  float bright = (far.x * 0.299 + far.y * 0.587 + far.z * 0.114) * (1.0 / 255.0);
  /* Outside the range when below its low end or above its high. */
  bool outside = ((bright - low) * (bright - high)) > 0.0;
  float3 rgb = floor((outside ? near : far) + 0.5);
  target.write(float4(rgb / 255.0, 1.0), id);
}
