/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * Clearwater's water on Metal: the shading of one ray, for the village.
 *
 * This is examples/capi/web/water.wgsl (lit_radiance and what it calls, and
 * grade_pixel) in Metal Shading Language. The names and the arithmetic are
 * the WGSL's, and its comments stay, so that a change to the water can be
 * carried over by reading the two side by side. The WGSL reads its tables from
 * global buffers. Metal cannot, so each function takes the buffers in a
 * `Water` first. build.sh joins this file in front of village.metal, which
 * holds the kernels that call it.
 *
 * The tables are the water's, packed by extensions/water/upload.mojo
 * (ComposeUpload): `frame_words` holds the frame values, the sizes and the
 * three level tables, at the words that M_* and *_TABLE name.
 */
#include <metal_stdlib>
using namespace metal;

/* The buffers that the water reads. */
struct Water {
  device const float *surface;
  device const float *ripple;
  device const float *caustic;
  device const float *pebble;
  constant uint *frame_words;
};

/* The words of `frame_words`: the frame values (extensions/water/upload.mojo,
 * frame_values) from word 0, then the sizes, then the three level tables. */
constant uint M_WIDTH = 24u;
constant uint M_HEIGHT = 25u;
constant uint M_RIPPLE_SIDE = 26u;
constant uint M_GRID_WIDTH = 27u;
constant uint M_GRID_HEIGHT = 28u;
constant uint SURFACE_TABLE = 32u;
constant uint CAUSTIC_TABLE = 96u;
constant uint PEBBLE_TABLE = 160u;
constant uint BASIN = 256u;
constant float PI = 3.141592653589793;
constant float IOR = 1.3335;
constant float CAUSTIC_LOD_BIAS = 1.0;

static float mf(thread const Water &ctx, uint word) {
    return as_type<float>(ctx.frame_words[word]);
}

// Entry `entry` of a table whose first word is `base`.
static int table(thread const Water &ctx, uint base, int entry) {
    return int(ctx.frame_words[base + 2u * uint(entry)]);
}

// Mojo's remainder is never negative, and WGSL's has the sign of the left side.
static int wrap(thread const Water &ctx, int index, int n) {
    const auto r = index % n;
    return select(r, r + n, r < 0);
}

static int clamp_index(thread const Water &ctx, int i, int n) {
    if (i < 0) {
        return 0;
    }
    if (i >= n) {
        return n - 1;
    }
    return i;
}

static float clamp01(thread const Water &ctx, float value) {
    if (value <= 0.0) {
        return 0.0;
    }
    if (value >= 1.0) {
        return 1.0;
    }
    return value;
}

// The builtin smoothstep is undefined when the edges are reversed, and the
// page's shader reverses them.
static float smooth_step(thread const Water &ctx, float edge0, float edge1, float value) {
    const auto t = clamp01(ctx, (value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

static float dot3(thread const Water &ctx, float3 a, float3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

static float3 unit(thread const Water &ctx, float3 v) {
    const auto length_ = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length_ > 0.0) {
        return v / length_;
    }
    return v;
}

static float4 blend4(thread const Water &ctx, float4 a, float4 b, float t) {
    const auto s = 1.0 - t;
    return a * s + b * t;
}

static float3 blend3(thread const Water &ctx, float3 a, float3 b, float t) {
    const auto s = 1.0 - t;
    return a * s + b * t;
}

static float3 exp3(thread const Water &ctx, float3 v) {
    return float3(exp(-v.x), exp(-v.y), exp(-v.z));
}

// ---------------------------------------------------------------------------
// Noise: optics.mojo. The hash is Clearwater's hash12. A fused multiply and add
// changes its low bits, and the shader cannot ask for an unfused one, so a
// glint or a speck can differ from the Mojo frame in a cell now and then.

static float hash12(thread const Water &ctx, float x, float y) {
    const auto c = 0.1031;
    const auto k = 33.33;
    auto px = fract(fma(x, c, 0.0));
    auto py = fract(fma(y, c, 0.0));
    auto pz = fract(fma(x, c, 0.0));
    const auto d = (fma(px, py + k, 0.0) + fma(py, pz + k, 0.0)) + fma(pz, px + k, 0.0);
    px = px + d;
    py = py + d;
    pz = pz + d;
    return fract(fma(px + py, pz, 0.0));
}

static float value_noise(thread const Water &ctx, float x, float y) {
    const auto ix = floor(x);
    const auto iy = floor(y);
    const auto fx = x - ix;
    const auto fy = y - iy;
    const auto ux = fx * fx * (3.0 - 2.0 * fx);
    const auto uy = fy * fy * (3.0 - 2.0 * fy);
    const auto a = hash12(ctx, ix, iy);
    const auto b = hash12(ctx, ix + 1.0, iy);
    const auto c = hash12(ctx, ix, iy + 1.0);
    const auto d = hash12(ctx, ix + 1.0, iy + 1.0);
    const auto ab = a + (b - a) * ux;
    const auto cd = c + (d - c) * ux;
    return ab + (cd - ab) * uy;
}

static float fbm2(thread const Water &ctx, float x, float y) {
    auto v = 0.0;
    auto a = 0.5;
    auto px = x;
    auto py = y;
    for (auto octave = 0; octave < 4; octave++) {
        v += a * value_noise(ctx, px, py);
        px = px * 2.03 + 17.1;
        py = py * 2.03 + 17.1;
        a *= 0.5;
    }
    return v;
}

// ---------------------------------------------------------------------------
// Optics: optics.mojo.

static float fresnel(thread const Water &ctx, float cos_i, float ior) {
    const auto ci = clamp01(ctx, cos_i);
    const auto st2 = (1.0 - ci * ci) / (ior * ior);
    if (st2 >= 1.0) {
        return 1.0;
    }
    const auto ct = sqrt(1.0 - st2);
    const auto rs = (ci - ior * ct) / (ci + ior * ct);
    const auto rp = (ior * ci - ct) / (ior * ci + ct);
    return 0.5 * (rs * rs + rp * rp);
}

// GLSL's refract. A total reflection gives the zero vector, which air into
// water cannot reach.
static float3 refract_(thread const Water &ctx, float3 i, float3 n, float eta) {
    const auto cosi = dot3(ctx, n, i);
    const auto k = 1.0 - eta * eta * (1.0 - cosi * cosi);
    if (k < 0.0) {
        return float3(0.0);
    }
    const auto scale = eta * cosi + sqrt(k);
    return eta * i - scale * n;
}

static float3 refracted_sun(thread const Water &ctx, float3 sun) {
    return refract_(ctx, -sun, float3(0.0, 1.0, 0.0), 1.0 / IOR);
}

static float beckmann(thread const Water &ctx, float nh, float alpha2) {
    if (nh <= 0.0 || alpha2 <= 0.0) {
        return 0.0;
    }
    auto c2 = nh * nh;
    if (c2 < 1e-4) {
        c2 = 1e-4;
    }
    const auto tan2 = (1.0 - c2) / c2;
    return exp(-tan2 / alpha2) / (PI * alpha2 * c2 * c2);
}

static float smith_visibility(thread const Water &ctx, float nl, float nv, float alpha2) {
    return 0.5 / (
        nl * sqrt(nv * nv * (1.0 - alpha2) + alpha2)
        + nv * sqrt(nl * nl * (1.0 - alpha2) + alpha2)
        + 1e-5
    );
}

static float aces_channel(thread const Water &ctx, float value) {
    auto x = value;
    if (x < 0.0) {
        x = 0.0;
    }
    const auto a = 2.51;
    const auto b = 0.03;
    const auto c = 2.43;
    const auto d = 0.59;
    const auto e = 0.14;
    return clamp01(ctx, (x * (a * x + b)) / (x * (c * x + d) + e));
}

static float3 sky_radiance(thread const Water &ctx, float3 dir, float3 sun) {
    const auto length_ = sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    auto d = dir;
    if (length_ > 0.0) {
        d = d / length_;
    }
    const auto mu = d.x * sun.x + d.y * sun.y + d.z * sun.z;
    const auto zen = float3(0.11, 0.27, 0.62);
    const auto hor = float3(0.66, 0.78, 0.90);
    const auto t = pow(clamp01(ctx, d.y), 0.42);
    auto color = float3(
        hor.x + (zen.x - hor.x) * t,
        hor.y + (zen.y - hor.y) * t,
        hor.z + (zen.z - hor.z) * t
    );
    auto glow = 0.0;
    if (mu > 0.0) {
        glow = 0.22 * pow(mu, 6.0) + 0.30 * pow(mu, 64.0) + 1.6 * pow(mu, 2400.0);
    }
    color = color + float3(1.0, 0.86, 0.66) * glow;
    const auto azimuth = atan2(d.z, d.x);
    auto ridge = 0.040
        + 0.016 * sin(azimuth * 2.0 + 0.7)
        + 0.011 * sin(azimuth * 5.0 + 2.1)
        + 0.006 * sin(azimuth * 11.0 + 0.3)
        + 0.003 * sin(azimuth * 23.0 + 1.7);
    ridge += 0.0045 * (value_noise(ctx, azimuth * 260.0, 0.0) - 0.5);
    ridge += 0.002 * (value_noise(ctx, azimuth * 900.0, 3.0) - 0.5);
    auto hx = d.x;
    auto hz = d.z;
    const auto hlen = sqrt(hx * hx + hz * hz);
    if (hlen > 1e-5) {
        hx /= hlen;
        hz /= hlen;
    }
    auto sx = sun.x;
    auto sz = sun.z;
    const auto slen = sqrt(sx * sx + sz * sz);
    if (slen > 1e-5) {
        sx /= slen;
        sz /= slen;
    }
    const auto back = smooth_step(ctx, -0.3, 0.95, hx * sx + hz * sz);
    const auto u = clamp01(ctx, d.y / ridge);
    const auto tex = fbm2(ctx, azimuth * 420.0, d.y * 420.0);
    const auto pine = 0.045 * (0.6 + 0.8 * tex);
    const auto rock = 0.30 * (
        0.55 + 0.7 * fbm2(ctx, azimuth * 420.0 * 1.7 + 5.0, d.y * 420.0 * 1.7 + 5.0)
    );
    const auto cliff = smooth_step(ctx, 0.42, 0.18, u + 0.25 * (tex - 0.5))
        * smooth_step(ctx, 0.35, 0.75, value_noise(ctx, azimuth * 18.0, 1.0));
    auto land_r = pine + (rock - pine) * cliff;
    auto land_g = 0.070 * (0.6 + 0.8 * tex)
        + (
            0.28 * (0.55 + 0.7 * fbm2(ctx, azimuth * 714.0 + 5.0, d.y * 714.0 + 5.0))
            - 0.070 * (0.6 + 0.8 * tex)
        ) * cliff;
    auto land_b = 0.042 * (0.6 + 0.8 * tex)
        + (
            0.23 * (0.55 + 0.7 * fbm2(ctx, azimuth * 714.0 + 5.0, d.y * 714.0 + 5.0))
            - 0.042 * (0.6 + 0.8 * tex)
        ) * cliff;
    const auto shade = 1.0 + (0.45 - 1.0) * back;
    land_r *= shade;
    land_g *= shade;
    land_b *= shade;
    const auto aerial = 0.38 + 0.25 * back;
    land_r = land_r + (hor.x * 0.92 - land_r) * aerial;
    land_g = land_g + (hor.y * 0.92 - land_g) * aerial;
    land_b = land_b + (hor.z * 0.92 - land_b) * aerial;
    auto cover = smooth_step(ctx, ridge + 2e-4, ridge - 2e-4, d.y);
    if (d.y < -0.3) {
        cover = 0.0;
    }
    return float3(
        color.x + (land_r - color.x) * cover,
        color.y + (land_g - color.y) * cover,
        color.z + (land_b - color.z) * cover
    );
}

static float floor_depth(thread const Water &ctx, float x, float z) {
    auto shelf = -z + 1.5;
    if (shelf < 0.0) {
        shelf = 0.0;
    }
    if (shelf > 14.0) {
        shelf = 14.0;
    }
    return 0.95
        + 0.17 * shelf
        + 0.30 * (value_noise(ctx, x * 0.22, z * 0.22) - 0.5)
        + 0.10 * (value_noise(ctx, x * 0.9 + 7.0, z * 0.9 + 7.0) - 0.5);
}

// The bed of the water's basin: optics.mojo's basin_depth and basin_mud.
static float basin_depth(thread const Water &ctx, float x, float z) {
    const auto radius = mf(ctx, BASIN + 2u);
    if (radius <= 0.0) {
        return floor_depth(ctx, x, z);
    }
    const auto dx = x - mf(ctx, BASIN);
    const auto dz = z - mf(ctx, BASIN + 1u);
    const auto r = sqrt(dx * dx + dz * dz);
    const auto inner = radius * mf(ctx, BASIN + 4u);
    const auto t = clamp01(ctx, (r - radius) / (inner - radius));
    const auto fall = t * t * (3.0 - 2.0 * t);
    const auto rim = mf(ctx, BASIN + 5u);
    return fall * (mf(ctx, BASIN + 3u) + rim) - rim;
}

static float basin_mud(thread const Water &ctx, float depth) {
    if (mf(ctx, BASIN + 2u) <= 0.0) {
        return 0.0;
    }
    return 0.85 * clamp01(ctx, 1.0 - depth / 0.35);
}

// ---------------------------------------------------------------------------
// Texture footprints: filter.mojo.

struct Step {
  float lod;
  int taps;
  float du;
  float dv;
};

static Step anisotropic_step(thread const Water &ctx, float du_dx, float dv_dx, float du_dy, float dv_dy, float width, float height, float max_aniso, float lod_bias, float max_lod) {
    const auto ax = du_dx * width;
    const auto ay = dv_dx * height;
    const auto bx = du_dy * width;
    const auto by = dv_dy * height;
    const auto len_x = sqrt(ax * ax + ay * ay);
    const auto len_y = sqrt(bx * bx + by * by);
    auto major = len_x;
    auto minor = len_y;
    auto du = du_dx;
    auto dv = dv_dx;
    if (len_y > len_x) {
        major = len_y;
        minor = len_x;
        du = du_dy;
        dv = dv_dy;
    }
    if (minor < 1e-8) {
        minor = 1e-8;
    }
    if (major < minor) {
        major = minor;
    }
    auto ratio = major / minor;
    if (ratio > max_aniso) {
        ratio = max_aniso;
    }
    auto lod = log(major / ratio) * 1.4426950408889634 + lod_bias;
    if (lod < 0.0) {
        lod = 0.0;
    }
    if (lod > max_lod) {
        lod = max_lod;
    }
    return Step{lod, int(ratio), du, dv};
}

// ---------------------------------------------------------------------------
// The ocean surface: surface.mojo. A texel is (height, slope x, slope z, slope
// squared).

static int surface_levels(thread const Water &ctx) {
    return table(ctx, SURFACE_TABLE, 0);
}

static int surface_side(thread const Water &ctx, int level) {
    return table(ctx, SURFACE_TABLE, 1 + 2 * max(level, 0));
}

static float4 surface_texel(thread const Water &ctx, int level, int x, int y) {
    const auto entry = 1 + 2 * max(level, 0);
    const auto side = table(ctx, SURFACE_TABLE, entry);
    const auto at = uint(table(ctx, SURFACE_TABLE, entry + 1) + (y * side + x) * 4);
    return float4(ctx.surface[at], ctx.surface[at + 1u], ctx.surface[at + 2u], ctx.surface[at + 3u]);
}

// One bilinear read of a level, repeating, at texture coordinates.
static float4 surface_bilinear(thread const Water &ctx, int level, float u, float v) {
    const auto n = surface_side(ctx, level);
    const auto px = u * float(n) - 0.5;
    const auto pz = v * float(n) - 0.5;
    auto x0 = int(floor(px));
    auto z0 = int(floor(pz));
    const auto fx = px - float(x0);
    const auto fz = pz - float(z0);
    const auto x1 = wrap(ctx, x0 + 1, n);
    const auto z1 = wrap(ctx, z0 + 1, n);
    x0 = wrap(ctx, x0, n);
    z0 = wrap(ctx, z0, n);
    const auto a = blend4(ctx, surface_texel(ctx, level, x0, z0), surface_texel(ctx, level, x1, z0), fx);
    const auto b = blend4(ctx, surface_texel(ctx, level, x0, z1), surface_texel(ctx, level, x1, z1), fx);
    return blend4(ctx, a, b, fz);
}

static float4 sample_surface(thread const Water &ctx, float x, float z) {
    const auto tile_length = mf(ctx, 16u);
    return surface_bilinear(ctx, 0, x / tile_length, z / tile_length);
}

// The page's cubic B-spline filter: four bilinear taps.
static float4 sample_surface_smooth(thread const Water &ctx, float x, float z) {
    const auto n = float(surface_side(ctx, 0));
    const auto tile_length = mf(ctx, 16u);
    const auto px = x / tile_length * n - 0.5;
    const auto pz = z / tile_length * n - 0.5;
    const auto ix = floor(px);
    const auto iz = floor(pz);
    const auto fx = px - ix;
    const auto fz = pz - iz;
    const auto fx2 = fx * fx;
    const auto fz2 = fz * fz;
    const auto fx3 = fx2 * fx;
    const auto fz3 = fz2 * fz;
    const auto wx0 = (-fx3 + 3.0 * fx2 - 3.0 * fx + 1.0) / 6.0;
    const auto wz0 = (-fz3 + 3.0 * fz2 - 3.0 * fz + 1.0) / 6.0;
    const auto wx1 = (3.0 * fx3 - 6.0 * fx2 + 4.0) / 6.0;
    const auto wz1 = (3.0 * fz3 - 6.0 * fz2 + 4.0) / 6.0;
    const auto wx2 = (-3.0 * fx3 + 3.0 * fx2 + 3.0 * fx + 1.0) / 6.0;
    const auto wz2 = (-3.0 * fz3 + 3.0 * fz2 + 3.0 * fz + 1.0) / 6.0;
    const auto wx3 = fx3 / 6.0;
    const auto wz3 = fz3 / 6.0;
    const auto gx0 = wx0 + wx1;
    const auto gz0 = wz0 + wz1;
    const auto gx1 = wx2 + wx3;
    const auto gz1 = wz2 + wz3;
    const auto h0x = (wx1 / gx0 - 0.5 + ix) / n * tile_length;
    const auto h1x = (wx3 / gx1 + 1.5 + ix) / n * tile_length;
    const auto h0z = (wz1 / gz0 - 0.5 + iz) / n * tile_length;
    const auto h1z = (wz3 / gz1 + 1.5 + iz) / n * tile_length;
    const auto s00 = sample_surface(ctx, h0x, h0z);
    const auto s10 = sample_surface(ctx, h1x, h0z);
    const auto s01 = sample_surface(ctx, h0x, h1z);
    const auto s11 = sample_surface(ctx, h1x, h1z);
    const auto top = s00 * gx0 + s10 * gx1;
    const auto bottom = s01 * gx0 + s11 * gx1;
    return top * gz0 + bottom * gz1;
}

static float4 surface_trilinear(thread const Water &ctx, float u, float v, float lod) {
    const auto levels = surface_levels(ctx);
    const auto i0 = int(floor(lod));
    auto i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    const auto frac = lod - float(i0);
    return blend4(ctx, surface_bilinear(ctx, i0, u, v), surface_bilinear(ctx, i1, u, v), frac);
}

static float4 sample_surface_filtered(thread const Water &ctx, float x, float z, float du_dx, float dv_dx, float du_dy, float dv_dy, bool cubic) {
    const auto side = float(surface_side(ctx, 0));
    const auto step_ = anisotropic_step(ctx, 
        du_dx, dv_dx, du_dy, dv_dy, side, side, 8.0, 0.0, float(surface_levels(ctx))
    );
    auto smooth_ = cubic;
    if (step_.lod > 0.0) {
        smooth_ = false;
    }
    if (step_.taps > 1) {
        smooth_ = false;
    }
    if (smooth_) {
        return sample_surface_smooth(ctx, x, z);
    }
    const auto tile_length = mf(ctx, 16u);
    const auto u = x / tile_length;
    const auto v = z / tile_length;
    auto acc = float4(0.0);
    const auto count = step_.taps;
    for (auto i = 0; i < count; i++) {
        const auto o = (float(i) + 0.5) / float(count) - 0.5;
        acc = acc + surface_trilinear(ctx, u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    return acc * (1.0 / float(count));
}

static float slope_variance(thread const Water &ctx, float4 s) {
    const auto raw = s.w - (s.y * s.y + s.z * s.z);
    if (raw < 0.0) {
        return 0.0;
    }
    return raw;
}

// ---------------------------------------------------------------------------
// The ripple window: ripple.mojo. A texel is (height, slope x, slope z,
// Laplacian).

static float4 ripple_texel(thread const Water &ctx, int n, int x, int y) {
    const auto at = uint((y * n + x) * 4);
    return float4(ctx.ripple[at], ctx.ripple[at + 1u], ctx.ripple[at + 2u], ctx.ripple[at + 3u]);
}

static float4 sample_ripple(thread const Water &ctx, float x, float z) {
    const auto size = mf(ctx, 17u);
    const auto u = (x - mf(ctx, 18u)) / size + 0.5;
    const auto v = (z - mf(ctx, 19u)) / size + 0.5;
    if (u < 0.0 || v < 0.0 || u > 1.0 || v > 1.0) {
        return float4(0.0);
    }
    const auto n = int(ctx.frame_words[M_RIPPLE_SIDE]);
    const auto px = u * float(n) - 0.5;
    const auto py = v * float(n) - 0.5;
    auto x0 = int(floor(px));
    auto y0 = int(floor(py));
    const auto fx = px - float(x0);
    const auto fy = py - float(y0);
    const auto x1 = clamp_index(ctx, x0 + 1, n);
    const auto y1 = clamp_index(ctx, y0 + 1, n);
    x0 = clamp_index(ctx, x0, n);
    y0 = clamp_index(ctx, y0, n);
    const auto w00 = (1.0 - fx) * (1.0 - fy);
    const auto w10 = fx * (1.0 - fy);
    const auto w01 = (1.0 - fx) * fy;
    const auto w11 = fx * fy;
    return ripple_texel(ctx, n, x0, y0) * w00 + ripple_texel(ctx, n, x1, y0) * w10
        + ripple_texel(ctx, n, x0, y1) * w01 + ripple_texel(ctx, n, x1, y1) * w11;
}

// ---------------------------------------------------------------------------
// The caustics: the _caustic_* functions of frame.mojo.

static int caustic_levels(thread const Water &ctx) {
    return table(ctx, CAUSTIC_TABLE, 0);
}

static int caustic_side(thread const Water &ctx, int level) {
    return table(ctx, CAUSTIC_TABLE, 1 + 2 * max(level, 0));
}

static float3 caustic_texel(thread const Water &ctx, int level, int x, int y) {
    const auto entry = 1 + 2 * max(level, 0);
    const auto side = table(ctx, CAUSTIC_TABLE, entry);
    const auto at = uint(table(ctx, CAUSTIC_TABLE, entry + 1) + (y * side + x) * 3);
    return float3(ctx.caustic[at], ctx.caustic[at + 1u], ctx.caustic[at + 2u]);
}

static float3 caustic_level(thread const Water &ctx, int level, float u, float v) {
    const auto n = caustic_side(ctx, level);
    const auto fu = u - floor(u);
    const auto fv = v - floor(v);
    const auto px = fu * float(n) - 0.5;
    const auto py = fv * float(n) - 0.5;
    const auto x0 = wrap(ctx, int(floor(px)), n);
    const auto y0 = wrap(ctx, int(floor(py)), n);
    const auto x1 = (x0 + 1) % n;
    const auto y1 = (y0 + 1) % n;
    const auto tx = px - floor(px);
    const auto ty = py - floor(py);
    const auto top = blend3(ctx, caustic_texel(ctx, level, x0, y0), caustic_texel(ctx, level, x1, y0), tx);
    const auto bottom = blend3(ctx, caustic_texel(ctx, level, x0, y1), caustic_texel(ctx, level, x1, y1), tx);
    return blend3(ctx, top, bottom, ty);
}

static float3 caustic_lod(thread const Water &ctx, float u, float v, float lod) {
    const auto levels = caustic_levels(ctx);
    const auto i0 = int(floor(lod));
    auto i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    const auto frac = lod - float(i0);
    return blend3(ctx, caustic_level(ctx, i0, u, v), caustic_level(ctx, i1, u, v), frac);
}

static float3 caustic_grad(thread const Water &ctx, float u, float v, float du_dx, float dv_dx, float du_dy, float dv_dy) {
    const auto side = float(caustic_side(ctx, 0));
    const auto step_ = anisotropic_step(ctx, 
        du_dx, dv_dx, du_dy, dv_dy, side, side, 8.0, CAUSTIC_LOD_BIAS, float(caustic_levels(ctx))
    );
    auto acc = float3(0.0);
    const auto count = step_.taps;
    for (auto i = 0; i < count; i++) {
        const auto o = (float(i) + 0.5) / float(count) - 0.5;
        acc = acc + caustic_lod(ctx, u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    const auto inv = 1.0 / float(count);
    return acc * inv;
}

// ---------------------------------------------------------------------------
// The pebble photograph: pebbles.mojo and bed_color in optics.mojo.

static int pebble_levels(thread const Water &ctx) {
    return table(ctx, PEBBLE_TABLE, 0);
}

static int pebble_width(thread const Water &ctx, int level) {
    return table(ctx, PEBBLE_TABLE, 1 + 3 * max(level, 0));
}

static int pebble_height(thread const Water &ctx, int level) {
    return table(ctx, PEBBLE_TABLE, 2 + 3 * max(level, 0));
}

static float3 pebble_texel(thread const Water &ctx, int level, int x, int y) {
    const auto entry = 1 + 3 * max(level, 0);
    const auto width = table(ctx, PEBBLE_TABLE, entry);
    const auto at = uint(table(ctx, PEBBLE_TABLE, entry + 2) + (y * width + x) * 3);
    return float3(ctx.pebble[at], ctx.pebble[at + 1u], ctx.pebble[at + 2u]);
}

static float3 pebble_level(thread const Water &ctx, int level, float u, float v) {
    const auto w = pebble_width(ctx, level);
    const auto h = pebble_height(ctx, level);
    const auto fu = u - floor(u);
    const auto fv = v - floor(v);
    const auto x = fu * float(w) - 0.5;
    const auto y = fv * float(h) - 0.5;
    const auto x0 = wrap(ctx, int(floor(x)), w);
    const auto y0 = wrap(ctx, int(floor(y)), h);
    const auto x1 = (x0 + 1) % w;
    const auto y1 = (y0 + 1) % h;
    const auto tx = x - floor(x);
    const auto ty = y - floor(y);
    const auto top = blend3(ctx, pebble_texel(ctx, level, x0, y0), pebble_texel(ctx, level, x1, y0), tx);
    const auto bottom = blend3(ctx, pebble_texel(ctx, level, x0, y1), pebble_texel(ctx, level, x1, y1), tx);
    return blend3(ctx, top, bottom, ty);
}

static float3 pebble_trilinear(thread const Water &ctx, float u, float v, float lod) {
    const auto levels = pebble_levels(ctx);
    const auto i0 = int(floor(lod));
    auto i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    const auto frac = lod - float(i0);
    return blend3(ctx, pebble_level(ctx, i0, u, v), pebble_level(ctx, i1, u, v), frac);
}

static float3 sample_pebble_grad(thread const Water &ctx, float u, float v, float du_dx, float dv_dx, float du_dy, float dv_dy) {
    const auto step_ = anisotropic_step(ctx, 
        du_dx, dv_dx, du_dy, dv_dy,
        float(pebble_width(ctx, 0)), float(pebble_height(ctx, 0)), 16.0, 0.0, float(pebble_levels(ctx))
    );
    auto acc = float3(0.0);
    const auto count = step_.taps;
    for (auto i = 0; i < count; i++) {
        const auto o = (float(i) + 0.5) / float(count) - 0.5;
        acc = acc + pebble_trilinear(ctx, u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    const auto inv = 1.0 / float(count);
    return acc * inv;
}

// Albedo and a pseudo-height for the bed: `rgb` and `height`.
struct BedColor {
  float3 rgb;
  float height;
};

static BedColor pebbles(thread const Water &ctx, float x, float z, float scale, float dx_x, float dx_z, float dy_x, float dy_z) {
    const auto meters = 0.78 * scale;
    const auto uv_x = x / meters;
    const auto uv_z = z / meters;
    const auto du_dx = dx_x / meters;
    const auto dv_dx = dx_z / meters;
    const auto du_dy = dy_x / meters;
    const auto dv_dy = dy_z / meters;
    const auto level = value_noise(ctx, x * 0.85, z * 0.85) * 8.0;
    const auto band = floor(level);
    const auto blend = level - band;
    const auto shift_u = sin(3.0 * band);
    const auto shift_v = sin(7.0 * band);
    const auto first = sample_pebble_grad(ctx, uv_x + shift_u, uv_z + shift_v, du_dx, dv_dx, du_dy, dv_dy);
    const auto next_band = band + 1.0;
    const auto next_u = sin(3.0 * next_band);
    const auto next_v = sin(7.0 * next_band);
    const auto second = sample_pebble_grad(ctx, uv_x + next_u, uv_z + next_v, du_dx, dv_dx, du_dy, dv_dy);
    const auto delta = (first.x - second.x) + (first.y - second.y) + (first.z - second.z);
    const auto mix_ = smooth_step(ctx, 0.2, 0.8, blend - 0.1 * delta);
    const auto color = blend3(ctx, first, second, mix_);
    // The page blurs the height lookup by six times the color footprint.
    const auto wide_a = sample_pebble_grad(ctx, 
        uv_x + shift_u, uv_z + shift_v, du_dx * 6.0, dv_dx * 6.0, du_dy * 6.0, dv_dy * 6.0
    );
    const auto wide_b = sample_pebble_grad(ctx, 
        uv_x + next_u, uv_z + next_v, du_dx * 6.0, dv_dx * 6.0, du_dy * 6.0, dv_dy * 6.0
    );
    const auto wide = blend3(ctx, wide_a, wide_b, mix_);
    return BedColor{color, wide.x * 0.3 + wide.y * 0.55 + wide.z * 0.15};
}

static BedColor bed_color(thread const Water &ctx, float x, float z, float dx_x, float dx_z, float dy_x, float dy_z) {
    const auto fine = pebbles(ctx, x, z, 1.0, dx_x, dx_z, dy_x, dy_z);
    const auto coarse = pebbles(ctx, -z + 5.3, x + 5.3, 1.7, -dx_z, dx_x, -dy_z, dy_x);
    const auto mix_c = smooth_step(ctx, 0.45, 0.62, fbm2(ctx, x * 0.21 + 40.0, z * 0.21 + 40.0));
    auto r = fine.rgb.x + (coarse.rgb.x - fine.rgb.x) * mix_c;
    auto g = fine.rgb.y + (coarse.rgb.y - fine.rgb.y) * mix_c;
    auto b = fine.rgb.z + (coarse.rgb.z - fine.rgb.z) * mix_c;
    auto h = fine.height + (coarse.height - fine.height) * mix_c;
    const auto zone = fbm2(ctx, x * 0.16 + 3.0, z * 0.16 + 3.0) + 0.10 * (value_noise(ctx, x * 2.5, z * 2.5) - 0.5);
    const auto marks = 0.5 + 0.5 * sin((x * 0.93 + z * 0.37) * 16.0 + 3.0 * value_noise(ctx, x * 0.8, z * 0.8));
    const auto sand_n = 0.82 + 0.22 * value_noise(ctx, x * 40.0, z * 40.0) + 0.10 * marks;
    auto sand_r = 0.60 * sand_n;
    auto sand_g = 0.55 * sand_n;
    auto sand_b = 0.44 * sand_n;
    sand_r = sand_r * sand_r * 1.4;
    sand_g = sand_g * sand_g * 1.4;
    sand_b = sand_b * sand_b * 1.4;
    const auto sand_m = smooth_step(ctx, h + 0.02, h + 0.16, (zone - 0.46) * 1.6);
    r = r + (sand_r - r) * sand_m;
    g = g + (sand_g - g) * sand_m;
    b = b + (sand_b - b) * sand_m;
    h = h + (0.42 + 0.05 * marks - h) * sand_m;
    const auto lum = r * 0.3 + g * 0.55 + b * 0.15;
    r = lum + (r - lum) * 0.8;
    g = lum + (g - lum) * 0.8;
    b = lum + (b - lum) * 0.8;
    r *= 1.10;
    b *= 0.86;
    const auto big = value_noise(ctx, x * 0.45, z * 0.45) * 0.65 + value_noise(ctx, x * 1.3 + 3.1, z * 1.3 + 3.1) * 0.35;
    const auto gain = 0.62 + (1.22 - 0.62) * big;
    r *= gain;
    g *= gain;
    b *= gain;
    const auto weed = smooth_step(ctx, 0.55, 0.85, value_noise(ctx, x * 0.32 + 11.0, z * 0.32 + 11.0));
    const auto weed_m = weed * 0.7;
    r = r + (r * 0.55 - r) * weed_m;
    g = g + (g * 0.62 - g) * weed_m;
    b = b + (b * 0.40 - b) * weed_m;
    const auto curve = 1.2;
    r = (0.30 + (pow(max(r, 0.0), curve) - 0.30) * 0.72) * 0.6;
    g = (0.29 + (pow(max(g, 0.0), curve) - 0.29) * 0.72) * 0.6;
    b = (0.27 + (pow(max(b, 0.0), curve) - 0.27) * 0.72) * 0.6;
    return BedColor{float3(r, g, b), h};
}

// ---------------------------------------------------------------------------
// The camera: frame.mojo.

struct Look {
  float3 f;
  float3 r;
  float3 u;
  float3 p;
};

static Look camera_look(thread const Water &ctx) {
    return Look{
        float3(mf(ctx, 0u), mf(ctx, 1u), mf(ctx, 2u)),
        float3(mf(ctx, 3u), mf(ctx, 4u), mf(ctx, 5u)),
        float3(mf(ctx, 6u), mf(ctx, 7u), mf(ctx, 8u)),
        float3(mf(ctx, 9u), mf(ctx, 10u), mf(ctx, 11u))
    };
}

// tan(32 degrees), the page's half field of view, in the bits that the Mojo
// frame uses.
static float tan_half_fov(thread const Water &ctx) {
    return as_type<float>(0x3F1FF770u);
}

static float3 view_ray(thread const Water &ctx, Look lk, float ndc_x, float ndc_y, float aspect) {
    const auto tan_f = tan_half_fov(ctx);
    return unit(ctx, float3(
        lk.f.x + ndc_x * aspect * tan_f * lk.r.x + ndc_y * tan_f * lk.u.x,
        lk.f.y + ndc_x * aspect * tan_f * lk.r.y + ndc_y * tan_f * lk.u.y,
        lk.f.z + ndc_x * aspect * tan_f * lk.r.z + ndc_y * tan_f * lk.u.z
    ));
}

static float2 plane_xz(thread const Water &ctx, Look lk, float ndc_x, float ndc_y, float aspect, float plane_y) {
    const auto rd = view_ray(ctx, lk, ndc_x, ndc_y, aspect);
    auto wdy = rd.y;
    if (wdy > -0.0015) {
        wdy = -0.0015;
    }
    const auto wd = unit(ctx, float3(rd.x, wdy, rd.z));
    const auto dist = (plane_y - lk.p.y) / wd.y;
    return float2(lk.p.x + wd.x * dist, lk.p.z + wd.z * dist);
}

// The change of the plane point over one pixel to the right and one up:
// (dpx_x, dpx_z, dpy_x, dpy_z).
static float4 footprint(thread const Water &ctx, Look lk, float ndc_x, float ndc_y, float aspect, float plane_y, float pixel_x, float pixel_y) {
    auto dpx_x = 0.0;
    auto dpx_z = 0.0;
    auto dpy_x = 0.0;
    auto dpy_z = 0.0;
    if (pixel_x != 0.0) {
        const auto here = plane_xz(ctx, lk, ndc_x, ndc_y, aspect, plane_y);
        const auto right = plane_xz(ctx, lk, ndc_x + pixel_x, ndc_y, aspect, plane_y);
        dpx_x = right.x - here.x;
        dpx_z = right.y - here.y;
    }
    if (pixel_y != 0.0) {
        const auto here = plane_xz(ctx, lk, ndc_x, ndc_y, aspect, plane_y);
        const auto up = plane_xz(ctx, lk, ndc_x, ndc_y + pixel_y, aspect, plane_y);
        dpy_x = up.x - here.x;
        dpy_z = up.y - here.y;
    }
    return float4(dpx_x, dpx_z, dpy_x, dpy_z);
}

// ---------------------------------------------------------------------------
// The water: lit_radiance and what it calls, in frame.mojo.

static float wave_height(thread const Water &ctx, float x, float z) {
    const auto a = sample_surface(ctx, x, z);
    const auto tile_length = mf(ctx, 16u);
    const auto b_uv_x = (0.8 * x + 0.6 * z) / (tile_length * 0.41) + 0.37;
    const auto b_uv_z = (-0.6 * x + 0.8 * z) / (tile_length * 0.41) + 0.37;
    const auto b = sample_surface(ctx, b_uv_x * tile_length, b_uv_z * tile_length);
    const auto rip = sample_ripple(ctx, x, z);
    return a.x + 0.10 * 0.41 * b.x + rip.x;
}

// (slope x, slope z, variance).
static float3 wave_slope(thread const Water &ctx, float x, float z, float dist, float4 foot) {
    const auto dpx_x = foot.x;
    const auto dpx_z = foot.y;
    const auto dpy_x = foot.z;
    const auto dpy_z = foot.w;
    const auto tile_length = mf(ctx, 16u);
    const auto a = sample_surface_filtered(ctx, 
        x, z, dpx_x / tile_length, dpx_z / tile_length, dpy_x / tile_length, dpy_z / tile_length, true
    );
    const auto tile = tile_length * 0.41;
    const auto b_uv_x = (0.8 * x + 0.6 * z) / tile + 0.37;
    const auto b_uv_z = (-0.6 * x + 0.8 * z) / tile + 0.37;
    const auto b = sample_surface_filtered(ctx, 
        b_uv_x * tile_length,
        b_uv_z * tile_length,
        (0.8 * dpx_x + 0.6 * dpx_z) / tile,
        (-0.6 * dpx_x + 0.8 * dpx_z) / tile,
        (0.8 * dpy_x + 0.6 * dpy_z) / tile,
        (-0.6 * dpy_x + 0.8 * dpy_z) / tile,
        true
    );
    const auto rip = sample_ripple(ctx, x, z);
    auto sx = a.y + 0.10 * (0.8 * b.y + 0.6 * b.z) + rip.y;
    auto sz = a.z + 0.10 * (-0.6 * b.y + 0.8 * b.z) + rip.z;
    const auto detail_tile = tile_length * 0.13;
    const auto c_uv_x = (0.28 * x - 0.96 * z) / detail_tile + 0.71;
    const auto c_uv_z = (0.96 * x + 0.28 * z) / detail_tile + 0.71;
    const auto c = sample_surface_filtered(ctx, 
        c_uv_x * tile_length,
        c_uv_z * tile_length,
        (0.28 * dpx_x - 0.96 * dpx_z) / detail_tile,
        (0.96 * dpx_x + 0.28 * dpx_z) / detail_tile,
        (0.28 * dpy_x - 0.96 * dpy_z) / detail_tile,
        (0.96 * dpy_x + 0.28 * dpy_z) / detail_tile,
        false
    );
    const auto detail = 0.13 * exp(-dist * 0.18);
    sx += detail * (0.28 * c.y + 0.96 * c.z);
    sz += detail * (-0.96 * c.y + 0.28 * c.z);
    const auto variance = slope_variance(ctx, a) + 0.01 * slope_variance(ctx, b);
    return float3(sx, sz, variance);
}

static float3 specks(thread const Water &ctx, float3 color, float x, float z, float3 ray, float travel, float clock, float3 sun_light) {
    auto result = color;
    for (auto k = 0; k < 3; k++) {
        const auto kf = float(k);
        const auto dz = 0.22 + 0.38 * kf;
        auto denom = -ray.y;
        if (denom < 0.05) {
            denom = 0.05;
        }
        const auto tt = dz / denom;
        const auto qx = (x + ray.x * tt) * 48.0 + clock * (0.05 + 0.03 * kf) + kf * 17.0;
        const auto qz = (z + ray.z * tt) * 48.0 + clock * 0.02 + kf * 17.0;
        const auto ix = floor(qx);
        const auto iz = floor(qz);
        const auto fx = qx - ix - 0.5;
        const auto fz = qz - iz - 0.5;
        const auto chance = hash12(ctx, ix + kf * 13.1, iz);
        const auto ox = hash12(ctx, ix + 3.1, iz) - 0.5;
        const auto oz = hash12(ctx, ix, iz + 7.7) - 0.5;
        const auto d = sqrt((fx - ox * 0.6) * (fx - ox * 0.6) + (fz - oz * 0.6) * (fz - oz * 0.6));
        if (chance > 0.988 && d < 0.10 && tt <= travel) {
            auto tint = float3(0.9, 1.0, 0.95);
            if (chance > 0.992) {
                tint = float3(0.4, 0.35, 0.3);
            }
            const auto gain = exp(-0.074 * tt * 2.0) * 0.022;
            result = result + tint * gain * sun_light.x;
        }
    }
    return result;
}

static float3 underwater(thread const Water &ctx, float x, float z, float height, float3 wd, float3 normal, float3 sun, float clock, float4 foot, float camera_t) {
    const auto dpx_x = foot.x;
    const auto dpx_z = foot.y;
    const auto dpy_x = foot.z;
    const auto dpy_z = foot.w;
    // Air into water cannot totally reflect, and a downward view stays downward.
    const auto ray = refract_(ctx, wd, normal, 1.0 / IOR);
    auto bed_x = x;
    auto bed_z = z;
    auto travel = 0.0;
    for (auto i = 0; i < 2; i++) {
        const auto depth = basin_depth(ctx, bed_x, bed_z);
        travel = (-depth - height) / ray.y;
        if (travel < 0.0) {
            travel = 0.0;
        }
        bed_x = x + ray.x * travel;
        bed_z = z + ray.z * travel;
    }
    auto span = camera_t;
    if (span < 0.05) {
        span = 0.05;
    }
    span = (span + travel) / span;
    auto bed = bed_color(ctx, bed_x, bed_z, dpx_x * span, dpx_z * span, dpy_x * span, dpy_z * span);
    const auto sun_ray = refracted_sun(ctx, sun);
    const auto ts = 1.0 - fresnel(ctx, sun.y, IOR);
    const auto bed_depth = basin_depth(ctx, bed_x, bed_z);
    auto column = height - (-bed_depth);
    if (column < 0.0) {
        column = 0.0;
    }
    // A basin's bed turns to mud where its water is shallow.
    const auto mud = basin_mud(ctx, bed_depth);
    bed.rgb = bed.rgb + (float3(0.075, 0.058, 0.040) - bed.rgb) * mud;
    const auto nudge = (bed.height - 0.35) * 0.05 / -sun_ray.y;
    const auto caustic_patch = mf(ctx, 20u);
    const auto cu = (bed_x - mf(ctx, 21u) + sun_ray.x * nudge) / caustic_patch;
    const auto cv = (bed_z - mf(ctx, 22u) + sun_ray.z * nudge) / caustic_patch;
    auto caus = caustic_grad(ctx, 
        cu,
        cv,
        dpx_x * span / caustic_patch,
        dpx_z * span / caustic_patch,
        dpy_x * span / caustic_patch,
        dpy_z * span / caustic_patch
    );
    const auto entered = sample_ripple(ctx, 
        bed_x - sun_ray.x * column / -sun_ray.y,
        bed_z - sun_ray.z * column / -sun_ray.y
    );
    auto focus = 1.0 / (1.0 + 0.12 * column * entered.w);
    if (focus < 0.45) {
        focus = 0.45;
    }
    if (focus > 3.0) {
        focus = 3.0;
    }
    caus = caus * focus;
    const auto sig_a = float3(0.40, 0.074, 0.088);
    const auto sig_s = float3(0.028, 0.052, 0.068);
    const auto sig_t = sig_a + sig_s;
    // The refracted sun determines the path length through the water.
    const auto sun_t_y = sun_ray.y;
    const auto absorb = exp3(ctx, sig_t * (column / -sun_t_y));
    const auto ao = 0.55 + 0.45 * smooth_step(ctx, 0.08, 0.42, bed.height);
    const auto sun_rgb = float3(1.0, 0.90, 0.74) * 6.0;
    const auto sun_light = sun_rgb * ts;
    const auto esun = float3(
        sun_light.x * absorb.x * caus.x * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.y * absorb.y * caus.y * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.z * absorb.z * caus.z * (-sun_t_y) * (0.75 + 0.25 * ao)
    );
    const auto sky_irr = float3(0.62, 0.70, 0.78) * (PI * 0.22);
    const auto sky_abs = exp3(ctx, (sig_a + sig_s * 0.4) * (column * 1.25));
    const auto esky = float3(sky_irr.x * sky_abs.x * ao, sky_irr.y * sky_abs.y * ao, sky_irr.z * sky_abs.z * ao);
    const auto floor_l = float3(
        bed.rgb.x / PI * (esun.x + esky.x),
        bed.rgb.y / PI * (esun.y + esky.y),
        bed.rgb.z / PI * (esun.z + esky.z)
    );
    const auto view_abs = exp3(ctx, sig_t * travel);
    const auto cos_s = sun_ray.x * (-ray.x) + sun_ray.y * (-ray.y) + sun_ray.z * (-ray.z);
    const auto g = 0.8;
    const auto phase = (1.0 - g * g) / (4.0 * PI * pow(1.0 + g * g - 2.0 * g * cos_s, 1.5));
    const auto mid_abs = exp3(ctx, sig_t * (column * 0.5 / -sun_t_y));
    const auto sky_mid = exp3(ctx, sig_a * (column * 0.6));
    const auto mid = float3(
        sun_light.x * mid_abs.x * (phase + 0.02) + sky_irr.x * sky_mid.x / (4.0 * PI),
        sun_light.y * mid_abs.y * (phase + 0.02) + sky_irr.y * sky_mid.y / (4.0 * PI),
        sun_light.z * mid_abs.z * (phase + 0.02) + sky_irr.z * sky_mid.z / (4.0 * PI)
    );
    const auto scatter = float3(
        sig_s.x / sig_t.x * mid.x * (1.0 - view_abs.x) * 3.2,
        sig_s.y / sig_t.y * mid.y * (1.0 - view_abs.y) * 3.2,
        sig_s.z / sig_t.z * mid.z * (1.0 - view_abs.z) * 3.2
    );
    const auto color = float3(
        floor_l.x * view_abs.x + scatter.x,
        floor_l.y * view_abs.y + scatter.y,
        floor_l.z * view_abs.z + scatter.z
    );
    return specks(ctx, color, x, z, ray, travel, clock, sun_light);
}

static float3 lit_radiance(thread const Water &ctx, Look lk, float ndc_x, float ndc_y, float aspect, float pixel_x, float pixel_y, float3 sun, float clock) {
    const auto rd = view_ray(ctx, lk, ndc_x, ndc_y, aspect);
    // Three fixed-point steps from the flat plane onto the waves.
    auto wdy = rd.y;
    if (wdy > -0.0015) {
        wdy = -0.0015;
    }
    const auto wd = unit(ctx, float3(rd.x, wdy, rd.z));
    auto t = -lk.p.y / wd.y;
    auto hit_x = 0.0;
    auto hit_z = 0.0;
    auto height = 0.0;
    for (auto s = 0; s < 3; s++) {
        hit_x = lk.p.x + wd.x * t;
        hit_z = lk.p.z + wd.z * t;
        height = wave_height(ctx, hit_x, hit_z);
        t = (height - lk.p.y) / wd.y;
    }
    const auto foot = footprint(ctx, lk, ndc_x, ndc_y, aspect, height, pixel_x, pixel_y);
    const auto slope = wave_slope(ctx, hit_x, hit_z, t, foot);
    auto normal = unit(ctx, float3(-slope.x, 1.0, -slope.y));
    const auto v = -wd;
    auto nv = dot3(ctx, normal, v);
    if (nv < 0.02) {
        normal = unit(ctx, float3(
            normal.x + v.x * (0.02 - nv),
            normal.y + v.y * (0.02 - nv),
            normal.z + v.z * (0.02 - nv)
        ));
        nv = dot3(ctx, normal, v);
    }
    const auto f = fresnel(ctx, nv, IOR);
    const auto incident_dot = dot3(ctx, normal, wd);
    auto reflected = float3(
        wd.x - 2.0 * incident_dot * normal.x,
        wd.y - 2.0 * incident_dot * normal.y,
        wd.z - 2.0 * incident_dot * normal.z
    );
    if (reflected.y < 0.0) {
        reflected = float3(reflected.x, -reflected.y, reflected.z);
    }
    const auto sky = sky_radiance(ctx, reflected, sun);
    const auto refl = sky * 1.25;
    const auto variance = slope.z;
    const auto alpha2 = 0.00012 + 1.2 * variance;
    const auto half_v = unit(ctx, float3(v.x + sun.x, v.y + sun.y, v.z + sun.z));
    auto nh = dot3(ctx, normal, half_v);
    auto nl = dot3(ctx, normal, sun);
    if (nh < 0.0) {
        nh = 0.0;
    }
    if (nl < 0.0) {
        nl = 0.0;
    }
    const auto dist = beckmann(ctx, nh, alpha2);
    const auto vis = smith_visibility(ctx, nl, nv, alpha2);
    const auto fh = fresnel(ctx, max(dot3(ctx, half_v, v), 0.0), IOR);
    const auto spec = dist * vis * fh * nl;
    const auto sun_rgb = float3(1.0, 0.90, 0.74) * (6.0 * spec);
    const auto under = underwater(ctx, hit_x, hit_z, height, wd, normal, sun, clock, foot, t);
    auto color = float3(
        f * refl.x + (1.0 - f) * under.x + sun_rgb.x,
        f * refl.y + (1.0 - f) * under.y + sun_rgb.y,
        f * refl.z + (1.0 - f) * under.z + sun_rgb.z
    );
    const auto haze = 1.0 - exp(-t * 0.004);
    const auto flat_ = unit(ctx, float3(wd.x, 0.0, wd.z));
    auto muh = flat_.x * sun.x + flat_.z * sun.z;
    if (muh < 0.0) {
        muh = 0.0;
    }
    const auto haze_c = float3(0.60, 0.71, 0.82)
        + float3(1.0, 0.86, 0.66) * (0.22 * pow(muh, 6.0) + 0.3 * pow(muh, 64.0));
    const auto haze_w = haze * 0.8;
    color = float3(
        color.x + (haze_c.x * 0.95 - color.x) * haze_w,
        color.y + (haze_c.y * 0.95 - color.y) * haze_w,
        color.z + (haze_c.z * 0.95 - color.z) * haze_w
    );
    auto above = sky_radiance(ctx, rd, sun);
    const auto mu = rd.x * sun.x + rd.y * sun.y + rd.z * sun.z;
    const auto disc = smooth_step(ctx, 0.99996, 0.999985, mu) * 18.0;
    above = above + float3(1.0, 0.90, 0.74) * (6.0 * disc);
    const auto horizon = smooth_step(ctx, -0.0005, 0.0015, rd.y);
    return float3(
        color.x + (above.x - color.x) * horizon,
        color.y + (above.y - color.y) * horizon,
        color.z + (above.z - color.z) * horizon
    );
}

// ---------------------------------------------------------------------------
// The post passes: post.mojo and grade_pixel in frame.mojo.

static float fract_time(thread const Water &ctx, float clock) {
    const auto t = clock * 7.13;
    return t - floor(t);
}

static float3 grade_pixel(thread const Water &ctx, float3 rgb, float3 glare, float3 bloom, uint x, uint y, uint width, uint height, float clock) {
    auto cr = rgb.x;
    auto cg = rgb.y;
    auto cb = rgb.z;
    cr += glare.x * 0.9 * 1000.0;
    cg += glare.y * 0.9 * 1000.0;
    cb += glare.z * 0.9 * 1000.0;
    cr += bloom.x * 0.035;
    cg += bloom.y * 0.035;
    cb += bloom.z * 0.035;
    cr *= 0.63;
    cg *= 0.63;
    cb *= 0.63;
    const auto u = (float(x) + 0.5) / float(width) - 0.5;
    const auto v = (float(y) + 0.5) / float(height) - 0.5;
    const auto vig = 1.0 - 0.22 * (u * u + (v * 0.8) * (v * 0.8)) * 2.2;
    cr *= vig;
    cg *= vig;
    cb *= vig;
    cr = aces_channel(ctx, cr);
    cg = aces_channel(ctx, cg);
    cb = aces_channel(ctx, cb);
    const auto lum = cr * 0.2126 + cg * 0.7152 + cb * 0.0722;
    cr = lum + (cr - lum) * 0.90;
    cg = lum + (cg - lum) * 0.90;
    cb = lum + (cb - lum) * 0.90;
    const auto shadow = 1.0 - smooth_step(ctx, 0.0, 0.35, lum);
    cr = cr + (cr * 0.96 - cr) * shadow;
    cg = cg + (cg * 1.0 - cg) * shadow;
    cb = cb + (cb * 1.05 - cb) * shadow;
    const auto gamma = 0.45454545;
    cr = pow(max(cr, 0.0), gamma);
    cg = pow(max(cg, 0.0), gamma);
    cb = pow(max(cb, 0.0), gamma);
    const auto grain = hash12(ctx, float(x) + fract_time(ctx, clock) * 917.0, float(y)) - 0.5;
    const auto amp = 0.018 * (1.0 - cr * 0.6);
    return float3(cr + grain * amp, cg + grain * amp, cb + grain * amp);
}

// A channel in 0 to 1 as a rounded, clamped byte.
static float to_byte(thread const Water &ctx, float value) {
    const auto scaled = clamp01(ctx, value) * 255.0 + 0.5;
    if (scaled <= 0.0) {
        return 0.0;
    }
    if (scaled >= 255.0) {
        return 255.0;
    }
    return floor(scaled);
}

// ---------------------------------------------------------------------------
