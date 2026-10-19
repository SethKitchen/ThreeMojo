// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// Clearwater's water on a WebGPU device: the per-pixel shader, the bloom and
// the grade.
//
// This is a port of extensions/water/frame.mojo (lit_radiance and what it
// calls), optics.mojo, post.mojo and the samplers of surface.mojo, ripple.mojo
// and pebbles.mojo. The names follow the Mojo names, and the arithmetic keeps
// the Mojo order, so that a change on one side is easy to carry to the other.
// The Mojo code that runs on a Metal or CUDA device reads the same arrays.
//
// The module's memory holds the arrays (window/capi_water.mojo, tm_gpu_part),
// and water_gpu.js writes them to the buffers below. A 64-bit table of the
// module becomes two 32-bit words an entry, and every entry is small, so the
// low word is the entry. The tables and the few frame values are in one buffer,
// `frame_words`, at the offsets that this file and water_gpu.js share.
//
// Passes, each one thread a pixel unless it says otherwise:
//   shade     radiance <- lit_radiance
//   sparks    samples  <- the glints at the glare grid's points (one thread a point)
//   bright    bloom_a  <- the part of the radiance that blooms
//   blur_h    bloom_b  <- bloom_a blurred along rows
//   blur_v    bloom_a  <- bloom_b blurred along columns
//   grade     picture  <- radiance, glare and bloom, graded and rounded to bytes
// The glare itself, one small FFT, runs in the module between sparks and grade.

@group(0) @binding(0) var<storage, read> surface: array<f32>;
@group(0) @binding(1) var<storage, read> ripple: array<f32>;
@group(0) @binding(2) var<storage, read> caustic: array<f32>;
@group(0) @binding(3) var<storage, read> pebble: array<f32>;
@group(0) @binding(4) var<storage, read> frame_words: array<u32>;
@group(0) @binding(5) var<storage, read_write> radiance: array<f32>;
@group(0) @binding(6) var<storage, read_write> bloom_a: array<f32>;
@group(0) @binding(7) var<storage, read_write> bloom_b: array<f32>;
@group(0) @binding(8) var<storage, read_write> samples: array<f32>;
@group(0) @binding(9) var<storage, read> grid: array<f32>;
@group(0) @binding(10) var picture: texture_storage_2d<rgba8unorm, write>;

// The words of `frame_words`: the frame values (extensions/water/upload.mojo,
// frame_values) from word 0, then the sizes, then the three level tables.
const M_WIDTH = 24u;
const M_HEIGHT = 25u;
const M_RIPPLE_SIDE = 26u;
const M_GRID_WIDTH = 27u;
const M_GRID_HEIGHT = 28u;
const SURFACE_TABLE = 32u;
const CAUSTIC_TABLE = 96u;
const PEBBLE_TABLE = 160u;

const PI = 3.141592653589793;
const IOR = 1.3335;
const CAUSTIC_LOD_BIAS = 1.0;

fn mf(word: u32) -> f32 {
    return bitcast<f32>(frame_words[word]);
}

// Entry `entry` of a table whose first word is `base`.
fn table(base: u32, entry: i32) -> i32 {
    return i32(frame_words[base + 2u * u32(entry)]);
}

// Mojo's remainder is never negative, and WGSL's has the sign of the left side.
fn wrap(index: i32, n: i32) -> i32 {
    let r = index % n;
    return select(r, r + n, r < 0);
}

fn clamp_index(i: i32, n: i32) -> i32 {
    if (i < 0) {
        return 0;
    }
    if (i >= n) {
        return n - 1;
    }
    return i;
}

fn clamp01(value: f32) -> f32 {
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
fn smooth_step(edge0: f32, edge1: f32, value: f32) -> f32 {
    let t = clamp01((value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

fn dot3(a: vec3<f32>, b: vec3<f32>) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn unit(v: vec3<f32>) -> vec3<f32> {
    let length_ = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length_ > 0.0) {
        return v / length_;
    }
    return v;
}

fn blend4(a: vec4<f32>, b: vec4<f32>, t: f32) -> vec4<f32> {
    let s = 1.0 - t;
    return a * s + b * t;
}

fn blend3(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    let s = 1.0 - t;
    return a * s + b * t;
}

fn exp3(v: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(exp(-v.x), exp(-v.y), exp(-v.z));
}

// ---------------------------------------------------------------------------
// Noise: optics.mojo. The hash is Clearwater's hash12. A fused multiply and add
// changes its low bits, and the shader cannot ask for an unfused one, so a
// glint or a speck can differ from the Mojo frame in a cell now and then.

fn hash12(x: f32, y: f32) -> f32 {
    let c = 0.1031;
    let k = 33.33;
    var px = fract(fma(x, c, 0.0));
    var py = fract(fma(y, c, 0.0));
    var pz = fract(fma(x, c, 0.0));
    let d = (fma(px, py + k, 0.0) + fma(py, pz + k, 0.0)) + fma(pz, px + k, 0.0);
    px = px + d;
    py = py + d;
    pz = pz + d;
    return fract(fma(px + py, pz, 0.0));
}

fn value_noise(x: f32, y: f32) -> f32 {
    let ix = floor(x);
    let iy = floor(y);
    let fx = x - ix;
    let fy = y - iy;
    let ux = fx * fx * (3.0 - 2.0 * fx);
    let uy = fy * fy * (3.0 - 2.0 * fy);
    let a = hash12(ix, iy);
    let b = hash12(ix + 1.0, iy);
    let c = hash12(ix, iy + 1.0);
    let d = hash12(ix + 1.0, iy + 1.0);
    let ab = a + (b - a) * ux;
    let cd = c + (d - c) * ux;
    return ab + (cd - ab) * uy;
}

fn fbm2(x: f32, y: f32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var px = x;
    var py = y;
    for (var octave = 0; octave < 4; octave++) {
        v += a * value_noise(px, py);
        px = px * 2.03 + 17.1;
        py = py * 2.03 + 17.1;
        a *= 0.5;
    }
    return v;
}

// ---------------------------------------------------------------------------
// Optics: optics.mojo.

fn fresnel(cos_i: f32, ior: f32) -> f32 {
    let ci = clamp01(cos_i);
    let st2 = (1.0 - ci * ci) / (ior * ior);
    if (st2 >= 1.0) {
        return 1.0;
    }
    let ct = sqrt(1.0 - st2);
    let rs = (ci - ior * ct) / (ci + ior * ct);
    let rp = (ior * ci - ct) / (ior * ci + ct);
    return 0.5 * (rs * rs + rp * rp);
}

// GLSL's refract. A total reflection gives the zero vector, which air into
// water cannot reach.
fn refract_(i: vec3<f32>, n: vec3<f32>, eta: f32) -> vec3<f32> {
    let cosi = dot3(n, i);
    let k = 1.0 - eta * eta * (1.0 - cosi * cosi);
    if (k < 0.0) {
        return vec3<f32>(0.0);
    }
    let scale = eta * cosi + sqrt(k);
    return eta * i - scale * n;
}

fn refracted_sun(sun: vec3<f32>) -> vec3<f32> {
    return refract_(-sun, vec3<f32>(0.0, 1.0, 0.0), 1.0 / IOR);
}

fn beckmann(nh: f32, alpha2: f32) -> f32 {
    if (nh <= 0.0 || alpha2 <= 0.0) {
        return 0.0;
    }
    var c2 = nh * nh;
    if (c2 < 1e-4) {
        c2 = 1e-4;
    }
    let tan2 = (1.0 - c2) / c2;
    return exp(-tan2 / alpha2) / (PI * alpha2 * c2 * c2);
}

fn smith_visibility(nl: f32, nv: f32, alpha2: f32) -> f32 {
    return 0.5 / (
        nl * sqrt(nv * nv * (1.0 - alpha2) + alpha2)
        + nv * sqrt(nl * nl * (1.0 - alpha2) + alpha2)
        + 1e-5
    );
}

fn aces_channel(value: f32) -> f32 {
    var x = value;
    if (x < 0.0) {
        x = 0.0;
    }
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp01((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn sky_radiance(dir: vec3<f32>, sun: vec3<f32>) -> vec3<f32> {
    let length_ = sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    var d = dir;
    if (length_ > 0.0) {
        d = d / length_;
    }
    let mu = d.x * sun.x + d.y * sun.y + d.z * sun.z;
    let zen = vec3<f32>(0.11, 0.27, 0.62);
    let hor = vec3<f32>(0.66, 0.78, 0.90);
    let t = pow(clamp01(d.y), 0.42);
    var color = vec3<f32>(
        hor.x + (zen.x - hor.x) * t,
        hor.y + (zen.y - hor.y) * t,
        hor.z + (zen.z - hor.z) * t,
    );
    var glow = 0.0;
    if (mu > 0.0) {
        glow = 0.22 * pow(mu, 6.0) + 0.30 * pow(mu, 64.0) + 1.6 * pow(mu, 2400.0);
    }
    color = color + vec3<f32>(1.0, 0.86, 0.66) * glow;
    let azimuth = atan2(d.z, d.x);
    var ridge = 0.040
        + 0.016 * sin(azimuth * 2.0 + 0.7)
        + 0.011 * sin(azimuth * 5.0 + 2.1)
        + 0.006 * sin(azimuth * 11.0 + 0.3)
        + 0.003 * sin(azimuth * 23.0 + 1.7);
    ridge += 0.0045 * (value_noise(azimuth * 260.0, 0.0) - 0.5);
    ridge += 0.002 * (value_noise(azimuth * 900.0, 3.0) - 0.5);
    var hx = d.x;
    var hz = d.z;
    let hlen = sqrt(hx * hx + hz * hz);
    if (hlen > 1e-5) {
        hx /= hlen;
        hz /= hlen;
    }
    var sx = sun.x;
    var sz = sun.z;
    let slen = sqrt(sx * sx + sz * sz);
    if (slen > 1e-5) {
        sx /= slen;
        sz /= slen;
    }
    let back = smooth_step(-0.3, 0.95, hx * sx + hz * sz);
    let u = clamp01(d.y / ridge);
    let tex = fbm2(azimuth * 420.0, d.y * 420.0);
    let pine = 0.045 * (0.6 + 0.8 * tex);
    let rock = 0.30 * (
        0.55 + 0.7 * fbm2(azimuth * 420.0 * 1.7 + 5.0, d.y * 420.0 * 1.7 + 5.0)
    );
    let cliff = smooth_step(0.42, 0.18, u + 0.25 * (tex - 0.5))
        * smooth_step(0.35, 0.75, value_noise(azimuth * 18.0, 1.0));
    var land_r = pine + (rock - pine) * cliff;
    var land_g = 0.070 * (0.6 + 0.8 * tex)
        + (
            0.28 * (0.55 + 0.7 * fbm2(azimuth * 714.0 + 5.0, d.y * 714.0 + 5.0))
            - 0.070 * (0.6 + 0.8 * tex)
        ) * cliff;
    var land_b = 0.042 * (0.6 + 0.8 * tex)
        + (
            0.23 * (0.55 + 0.7 * fbm2(azimuth * 714.0 + 5.0, d.y * 714.0 + 5.0))
            - 0.042 * (0.6 + 0.8 * tex)
        ) * cliff;
    let shade = 1.0 + (0.45 - 1.0) * back;
    land_r *= shade;
    land_g *= shade;
    land_b *= shade;
    let aerial = 0.38 + 0.25 * back;
    land_r = land_r + (hor.x * 0.92 - land_r) * aerial;
    land_g = land_g + (hor.y * 0.92 - land_g) * aerial;
    land_b = land_b + (hor.z * 0.92 - land_b) * aerial;
    var cover = smooth_step(ridge + 2e-4, ridge - 2e-4, d.y);
    if (d.y < -0.3) {
        cover = 0.0;
    }
    return vec3<f32>(
        color.x + (land_r - color.x) * cover,
        color.y + (land_g - color.y) * cover,
        color.z + (land_b - color.z) * cover,
    );
}

fn floor_depth(x: f32, z: f32) -> f32 {
    var shelf = -z + 1.5;
    if (shelf < 0.0) {
        shelf = 0.0;
    }
    if (shelf > 14.0) {
        shelf = 14.0;
    }
    return 0.95
        + 0.17 * shelf
        + 0.30 * (value_noise(x * 0.22, z * 0.22) - 0.5)
        + 0.10 * (value_noise(x * 0.9 + 7.0, z * 0.9 + 7.0) - 0.5);
}

// ---------------------------------------------------------------------------
// Texture footprints: filter.mojo.

struct Step {
    lod: f32,
    taps: i32,
    du: f32,
    dv: f32,
}

fn anisotropic_step(
    du_dx: f32, dv_dx: f32, du_dy: f32, dv_dy: f32,
    width: f32, height: f32, max_aniso: f32, lod_bias: f32, max_lod: f32,
) -> Step {
    let ax = du_dx * width;
    let ay = dv_dx * height;
    let bx = du_dy * width;
    let by = dv_dy * height;
    let len_x = sqrt(ax * ax + ay * ay);
    let len_y = sqrt(bx * bx + by * by);
    var major = len_x;
    var minor = len_y;
    var du = du_dx;
    var dv = dv_dx;
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
    var ratio = major / minor;
    if (ratio > max_aniso) {
        ratio = max_aniso;
    }
    var lod = log(major / ratio) * 1.4426950408889634 + lod_bias;
    if (lod < 0.0) {
        lod = 0.0;
    }
    if (lod > max_lod) {
        lod = max_lod;
    }
    return Step(lod, i32(ratio), du, dv);
}

// ---------------------------------------------------------------------------
// The ocean surface: surface.mojo. A texel is (height, slope x, slope z, slope
// squared).

fn surface_levels() -> i32 {
    return table(SURFACE_TABLE, 0);
}

fn surface_side(level: i32) -> i32 {
    return table(SURFACE_TABLE, 1 + 2 * max(level, 0));
}

fn surface_texel(level: i32, x: i32, y: i32) -> vec4<f32> {
    let entry = 1 + 2 * max(level, 0);
    let side = table(SURFACE_TABLE, entry);
    let at = u32(table(SURFACE_TABLE, entry + 1) + (y * side + x) * 4);
    return vec4<f32>(surface[at], surface[at + 1u], surface[at + 2u], surface[at + 3u]);
}

// One bilinear read of a level, repeating, at texture coordinates.
fn surface_bilinear(level: i32, u: f32, v: f32) -> vec4<f32> {
    let n = surface_side(level);
    let px = u * f32(n) - 0.5;
    let pz = v * f32(n) - 0.5;
    var x0 = i32(floor(px));
    var z0 = i32(floor(pz));
    let fx = px - f32(x0);
    let fz = pz - f32(z0);
    let x1 = wrap(x0 + 1, n);
    let z1 = wrap(z0 + 1, n);
    x0 = wrap(x0, n);
    z0 = wrap(z0, n);
    let a = blend4(surface_texel(level, x0, z0), surface_texel(level, x1, z0), fx);
    let b = blend4(surface_texel(level, x0, z1), surface_texel(level, x1, z1), fx);
    return blend4(a, b, fz);
}

fn sample_surface(x: f32, z: f32) -> vec4<f32> {
    let tile_length = mf(16u);
    return surface_bilinear(0, x / tile_length, z / tile_length);
}

// The page's cubic B-spline filter: four bilinear taps.
fn sample_surface_smooth(x: f32, z: f32) -> vec4<f32> {
    let n = f32(surface_side(0));
    let tile_length = mf(16u);
    let px = x / tile_length * n - 0.5;
    let pz = z / tile_length * n - 0.5;
    let ix = floor(px);
    let iz = floor(pz);
    let fx = px - ix;
    let fz = pz - iz;
    let fx2 = fx * fx;
    let fz2 = fz * fz;
    let fx3 = fx2 * fx;
    let fz3 = fz2 * fz;
    let wx0 = (-fx3 + 3.0 * fx2 - 3.0 * fx + 1.0) / 6.0;
    let wz0 = (-fz3 + 3.0 * fz2 - 3.0 * fz + 1.0) / 6.0;
    let wx1 = (3.0 * fx3 - 6.0 * fx2 + 4.0) / 6.0;
    let wz1 = (3.0 * fz3 - 6.0 * fz2 + 4.0) / 6.0;
    let wx2 = (-3.0 * fx3 + 3.0 * fx2 + 3.0 * fx + 1.0) / 6.0;
    let wz2 = (-3.0 * fz3 + 3.0 * fz2 + 3.0 * fz + 1.0) / 6.0;
    let wx3 = fx3 / 6.0;
    let wz3 = fz3 / 6.0;
    let gx0 = wx0 + wx1;
    let gz0 = wz0 + wz1;
    let gx1 = wx2 + wx3;
    let gz1 = wz2 + wz3;
    let h0x = (wx1 / gx0 - 0.5 + ix) / n * tile_length;
    let h1x = (wx3 / gx1 + 1.5 + ix) / n * tile_length;
    let h0z = (wz1 / gz0 - 0.5 + iz) / n * tile_length;
    let h1z = (wz3 / gz1 + 1.5 + iz) / n * tile_length;
    let s00 = sample_surface(h0x, h0z);
    let s10 = sample_surface(h1x, h0z);
    let s01 = sample_surface(h0x, h1z);
    let s11 = sample_surface(h1x, h1z);
    let top = s00 * gx0 + s10 * gx1;
    let bottom = s01 * gx0 + s11 * gx1;
    return top * gz0 + bottom * gz1;
}

fn surface_trilinear(u: f32, v: f32, lod: f32) -> vec4<f32> {
    let levels = surface_levels();
    let i0 = i32(floor(lod));
    var i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    let frac = lod - f32(i0);
    return blend4(surface_bilinear(i0, u, v), surface_bilinear(i1, u, v), frac);
}

fn sample_surface_filtered(
    x: f32, z: f32, du_dx: f32, dv_dx: f32, du_dy: f32, dv_dy: f32, cubic: bool,
) -> vec4<f32> {
    let side = f32(surface_side(0));
    let step_ = anisotropic_step(
        du_dx, dv_dx, du_dy, dv_dy, side, side, 8.0, 0.0, f32(surface_levels()),
    );
    var smooth_ = cubic;
    if (step_.lod > 0.0) {
        smooth_ = false;
    }
    if (step_.taps > 1) {
        smooth_ = false;
    }
    if (smooth_) {
        return sample_surface_smooth(x, z);
    }
    let tile_length = mf(16u);
    let u = x / tile_length;
    let v = z / tile_length;
    var acc = vec4<f32>(0.0);
    let count = step_.taps;
    for (var i = 0; i < count; i++) {
        let o = (f32(i) + 0.5) / f32(count) - 0.5;
        acc = acc + surface_trilinear(u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    return acc * (1.0 / f32(count));
}

fn slope_variance(s: vec4<f32>) -> f32 {
    let raw = s.w - (s.y * s.y + s.z * s.z);
    if (raw < 0.0) {
        return 0.0;
    }
    return raw;
}

// ---------------------------------------------------------------------------
// The ripple window: ripple.mojo. A texel is (height, slope x, slope z,
// Laplacian).

fn ripple_texel(n: i32, x: i32, y: i32) -> vec4<f32> {
    let at = u32((y * n + x) * 4);
    return vec4<f32>(ripple[at], ripple[at + 1u], ripple[at + 2u], ripple[at + 3u]);
}

fn sample_ripple(x: f32, z: f32) -> vec4<f32> {
    let size = mf(17u);
    let u = (x - mf(18u)) / size + 0.5;
    let v = (z - mf(19u)) / size + 0.5;
    if (u < 0.0 || v < 0.0 || u > 1.0 || v > 1.0) {
        return vec4<f32>(0.0);
    }
    let n = i32(frame_words[M_RIPPLE_SIDE]);
    let px = u * f32(n) - 0.5;
    let py = v * f32(n) - 0.5;
    var x0 = i32(floor(px));
    var y0 = i32(floor(py));
    let fx = px - f32(x0);
    let fy = py - f32(y0);
    let x1 = clamp_index(x0 + 1, n);
    let y1 = clamp_index(y0 + 1, n);
    x0 = clamp_index(x0, n);
    y0 = clamp_index(y0, n);
    let w00 = (1.0 - fx) * (1.0 - fy);
    let w10 = fx * (1.0 - fy);
    let w01 = (1.0 - fx) * fy;
    let w11 = fx * fy;
    return ripple_texel(n, x0, y0) * w00 + ripple_texel(n, x1, y0) * w10
        + ripple_texel(n, x0, y1) * w01 + ripple_texel(n, x1, y1) * w11;
}

// ---------------------------------------------------------------------------
// The caustics: the _caustic_* functions of frame.mojo.

fn caustic_levels() -> i32 {
    return table(CAUSTIC_TABLE, 0);
}

fn caustic_side(level: i32) -> i32 {
    return table(CAUSTIC_TABLE, 1 + 2 * max(level, 0));
}

fn caustic_texel(level: i32, x: i32, y: i32) -> vec3<f32> {
    let entry = 1 + 2 * max(level, 0);
    let side = table(CAUSTIC_TABLE, entry);
    let at = u32(table(CAUSTIC_TABLE, entry + 1) + (y * side + x) * 3);
    return vec3<f32>(caustic[at], caustic[at + 1u], caustic[at + 2u]);
}

fn caustic_level(level: i32, u: f32, v: f32) -> vec3<f32> {
    let n = caustic_side(level);
    let fu = u - floor(u);
    let fv = v - floor(v);
    let px = fu * f32(n) - 0.5;
    let py = fv * f32(n) - 0.5;
    let x0 = wrap(i32(floor(px)), n);
    let y0 = wrap(i32(floor(py)), n);
    let x1 = (x0 + 1) % n;
    let y1 = (y0 + 1) % n;
    let tx = px - floor(px);
    let ty = py - floor(py);
    let top = blend3(caustic_texel(level, x0, y0), caustic_texel(level, x1, y0), tx);
    let bottom = blend3(caustic_texel(level, x0, y1), caustic_texel(level, x1, y1), tx);
    return blend3(top, bottom, ty);
}

fn caustic_lod(u: f32, v: f32, lod: f32) -> vec3<f32> {
    let levels = caustic_levels();
    let i0 = i32(floor(lod));
    var i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    let frac = lod - f32(i0);
    return blend3(caustic_level(i0, u, v), caustic_level(i1, u, v), frac);
}

fn caustic_grad(u: f32, v: f32, du_dx: f32, dv_dx: f32, du_dy: f32, dv_dy: f32) -> vec3<f32> {
    let side = f32(caustic_side(0));
    let step_ = anisotropic_step(
        du_dx, dv_dx, du_dy, dv_dy, side, side, 8.0, CAUSTIC_LOD_BIAS, f32(caustic_levels()),
    );
    var acc = vec3<f32>(0.0);
    let count = step_.taps;
    for (var i = 0; i < count; i++) {
        let o = (f32(i) + 0.5) / f32(count) - 0.5;
        acc = acc + caustic_lod(u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    let inv = 1.0 / f32(count);
    return acc * inv;
}

// ---------------------------------------------------------------------------
// The pebble photograph: pebbles.mojo and bed_color in optics.mojo.

fn pebble_levels() -> i32 {
    return table(PEBBLE_TABLE, 0);
}

fn pebble_width(level: i32) -> i32 {
    return table(PEBBLE_TABLE, 1 + 3 * max(level, 0));
}

fn pebble_height(level: i32) -> i32 {
    return table(PEBBLE_TABLE, 2 + 3 * max(level, 0));
}

fn pebble_texel(level: i32, x: i32, y: i32) -> vec3<f32> {
    let entry = 1 + 3 * max(level, 0);
    let width = table(PEBBLE_TABLE, entry);
    let at = u32(table(PEBBLE_TABLE, entry + 2) + (y * width + x) * 3);
    return vec3<f32>(pebble[at], pebble[at + 1u], pebble[at + 2u]);
}

fn pebble_level(level: i32, u: f32, v: f32) -> vec3<f32> {
    let w = pebble_width(level);
    let h = pebble_height(level);
    let fu = u - floor(u);
    let fv = v - floor(v);
    let x = fu * f32(w) - 0.5;
    let y = fv * f32(h) - 0.5;
    let x0 = wrap(i32(floor(x)), w);
    let y0 = wrap(i32(floor(y)), h);
    let x1 = (x0 + 1) % w;
    let y1 = (y0 + 1) % h;
    let tx = x - floor(x);
    let ty = y - floor(y);
    let top = blend3(pebble_texel(level, x0, y0), pebble_texel(level, x1, y0), tx);
    let bottom = blend3(pebble_texel(level, x0, y1), pebble_texel(level, x1, y1), tx);
    return blend3(top, bottom, ty);
}

fn pebble_trilinear(u: f32, v: f32, lod: f32) -> vec3<f32> {
    let levels = pebble_levels();
    let i0 = i32(floor(lod));
    var i1 = i0 + 1;
    if (i1 > levels) {
        i1 = levels;
    }
    let frac = lod - f32(i0);
    return blend3(pebble_level(i0, u, v), pebble_level(i1, u, v), frac);
}

fn sample_pebble_grad(
    u: f32, v: f32, du_dx: f32, dv_dx: f32, du_dy: f32, dv_dy: f32,
) -> vec3<f32> {
    let step_ = anisotropic_step(
        du_dx, dv_dx, du_dy, dv_dy,
        f32(pebble_width(0)), f32(pebble_height(0)), 16.0, 0.0, f32(pebble_levels()),
    );
    var acc = vec3<f32>(0.0);
    let count = step_.taps;
    for (var i = 0; i < count; i++) {
        let o = (f32(i) + 0.5) / f32(count) - 0.5;
        acc = acc + pebble_trilinear(u + step_.du * o, v + step_.dv * o, step_.lod);
    }
    let inv = 1.0 / f32(count);
    return acc * inv;
}

// Albedo and a pseudo-height for the bed: `rgb` and `height`.
struct BedColor {
    rgb: vec3<f32>,
    height: f32,
}

fn pebbles(
    x: f32, z: f32, scale: f32, dx_x: f32, dx_z: f32, dy_x: f32, dy_z: f32,
) -> BedColor {
    let meters = 0.78 * scale;
    let uv_x = x / meters;
    let uv_z = z / meters;
    let du_dx = dx_x / meters;
    let dv_dx = dx_z / meters;
    let du_dy = dy_x / meters;
    let dv_dy = dy_z / meters;
    let level = value_noise(x * 0.85, z * 0.85) * 8.0;
    let band = floor(level);
    let blend = level - band;
    let shift_u = sin(3.0 * band);
    let shift_v = sin(7.0 * band);
    let first = sample_pebble_grad(uv_x + shift_u, uv_z + shift_v, du_dx, dv_dx, du_dy, dv_dy);
    let next_band = band + 1.0;
    let next_u = sin(3.0 * next_band);
    let next_v = sin(7.0 * next_band);
    let second = sample_pebble_grad(uv_x + next_u, uv_z + next_v, du_dx, dv_dx, du_dy, dv_dy);
    let delta = (first.x - second.x) + (first.y - second.y) + (first.z - second.z);
    let mix_ = smooth_step(0.2, 0.8, blend - 0.1 * delta);
    let color = blend3(first, second, mix_);
    // The page blurs the height lookup by six times the color footprint.
    let wide_a = sample_pebble_grad(
        uv_x + shift_u, uv_z + shift_v, du_dx * 6.0, dv_dx * 6.0, du_dy * 6.0, dv_dy * 6.0,
    );
    let wide_b = sample_pebble_grad(
        uv_x + next_u, uv_z + next_v, du_dx * 6.0, dv_dx * 6.0, du_dy * 6.0, dv_dy * 6.0,
    );
    let wide = blend3(wide_a, wide_b, mix_);
    return BedColor(color, wide.x * 0.3 + wide.y * 0.55 + wide.z * 0.15);
}

fn bed_color(x: f32, z: f32, dx_x: f32, dx_z: f32, dy_x: f32, dy_z: f32) -> BedColor {
    let fine = pebbles(x, z, 1.0, dx_x, dx_z, dy_x, dy_z);
    let coarse = pebbles(-z + 5.3, x + 5.3, 1.7, -dx_z, dx_x, -dy_z, dy_x);
    let mix_c = smooth_step(0.45, 0.62, fbm2(x * 0.21 + 40.0, z * 0.21 + 40.0));
    var r = fine.rgb.x + (coarse.rgb.x - fine.rgb.x) * mix_c;
    var g = fine.rgb.y + (coarse.rgb.y - fine.rgb.y) * mix_c;
    var b = fine.rgb.z + (coarse.rgb.z - fine.rgb.z) * mix_c;
    var h = fine.height + (coarse.height - fine.height) * mix_c;
    let zone = fbm2(x * 0.16 + 3.0, z * 0.16 + 3.0) + 0.10 * (value_noise(x * 2.5, z * 2.5) - 0.5);
    let marks = 0.5 + 0.5 * sin((x * 0.93 + z * 0.37) * 16.0 + 3.0 * value_noise(x * 0.8, z * 0.8));
    let sand_n = 0.82 + 0.22 * value_noise(x * 40.0, z * 40.0) + 0.10 * marks;
    var sand_r = 0.60 * sand_n;
    var sand_g = 0.55 * sand_n;
    var sand_b = 0.44 * sand_n;
    sand_r = sand_r * sand_r * 1.4;
    sand_g = sand_g * sand_g * 1.4;
    sand_b = sand_b * sand_b * 1.4;
    let sand_m = smooth_step(h + 0.02, h + 0.16, (zone - 0.46) * 1.6);
    r = r + (sand_r - r) * sand_m;
    g = g + (sand_g - g) * sand_m;
    b = b + (sand_b - b) * sand_m;
    h = h + (0.42 + 0.05 * marks - h) * sand_m;
    let lum = r * 0.3 + g * 0.55 + b * 0.15;
    r = lum + (r - lum) * 0.8;
    g = lum + (g - lum) * 0.8;
    b = lum + (b - lum) * 0.8;
    r *= 1.10;
    b *= 0.86;
    let big = value_noise(x * 0.45, z * 0.45) * 0.65 + value_noise(x * 1.3 + 3.1, z * 1.3 + 3.1) * 0.35;
    let gain = 0.62 + (1.22 - 0.62) * big;
    r *= gain;
    g *= gain;
    b *= gain;
    let weed = smooth_step(0.55, 0.85, value_noise(x * 0.32 + 11.0, z * 0.32 + 11.0));
    let weed_m = weed * 0.7;
    r = r + (r * 0.55 - r) * weed_m;
    g = g + (g * 0.62 - g) * weed_m;
    b = b + (b * 0.40 - b) * weed_m;
    let curve = 1.2;
    r = (0.30 + (pow(max(r, 0.0), curve) - 0.30) * 0.72) * 0.6;
    g = (0.29 + (pow(max(g, 0.0), curve) - 0.29) * 0.72) * 0.6;
    b = (0.27 + (pow(max(b, 0.0), curve) - 0.27) * 0.72) * 0.6;
    return BedColor(vec3<f32>(r, g, b), h);
}

// ---------------------------------------------------------------------------
// The camera: frame.mojo.

struct Look {
    f: vec3<f32>,
    r: vec3<f32>,
    u: vec3<f32>,
    p: vec3<f32>,
}

fn camera_look() -> Look {
    return Look(
        vec3<f32>(mf(0u), mf(1u), mf(2u)),
        vec3<f32>(mf(3u), mf(4u), mf(5u)),
        vec3<f32>(mf(6u), mf(7u), mf(8u)),
        vec3<f32>(mf(9u), mf(10u), mf(11u)),
    );
}

// tan(32 degrees), the page's half field of view, in the bits that the Mojo
// frame uses.
fn tan_half_fov() -> f32 {
    return bitcast<f32>(0x3F1FF770u);
}

fn view_ray(lk: Look, ndc_x: f32, ndc_y: f32, aspect: f32) -> vec3<f32> {
    let tan_f = tan_half_fov();
    return unit(vec3<f32>(
        lk.f.x + ndc_x * aspect * tan_f * lk.r.x + ndc_y * tan_f * lk.u.x,
        lk.f.y + ndc_x * aspect * tan_f * lk.r.y + ndc_y * tan_f * lk.u.y,
        lk.f.z + ndc_x * aspect * tan_f * lk.r.z + ndc_y * tan_f * lk.u.z,
    ));
}

fn plane_xz(lk: Look, ndc_x: f32, ndc_y: f32, aspect: f32, plane_y: f32) -> vec2<f32> {
    let rd = view_ray(lk, ndc_x, ndc_y, aspect);
    var wdy = rd.y;
    if (wdy > -0.0015) {
        wdy = -0.0015;
    }
    let wd = unit(vec3<f32>(rd.x, wdy, rd.z));
    let dist = (plane_y - lk.p.y) / wd.y;
    return vec2<f32>(lk.p.x + wd.x * dist, lk.p.z + wd.z * dist);
}

// The change of the plane point over one pixel to the right and one up:
// (dpx_x, dpx_z, dpy_x, dpy_z).
fn footprint(
    lk: Look, ndc_x: f32, ndc_y: f32, aspect: f32, plane_y: f32, pixel_x: f32, pixel_y: f32,
) -> vec4<f32> {
    var dpx_x = 0.0;
    var dpx_z = 0.0;
    var dpy_x = 0.0;
    var dpy_z = 0.0;
    if (pixel_x != 0.0) {
        let here = plane_xz(lk, ndc_x, ndc_y, aspect, plane_y);
        let right = plane_xz(lk, ndc_x + pixel_x, ndc_y, aspect, plane_y);
        dpx_x = right.x - here.x;
        dpx_z = right.y - here.y;
    }
    if (pixel_y != 0.0) {
        let here = plane_xz(lk, ndc_x, ndc_y, aspect, plane_y);
        let up = plane_xz(lk, ndc_x, ndc_y + pixel_y, aspect, plane_y);
        dpy_x = up.x - here.x;
        dpy_z = up.y - here.y;
    }
    return vec4<f32>(dpx_x, dpx_z, dpy_x, dpy_z);
}

// ---------------------------------------------------------------------------
// The water: lit_radiance and what it calls, in frame.mojo.

fn wave_height(x: f32, z: f32) -> f32 {
    let a = sample_surface(x, z);
    let tile_length = mf(16u);
    let b_uv_x = (0.8 * x + 0.6 * z) / (tile_length * 0.41) + 0.37;
    let b_uv_z = (-0.6 * x + 0.8 * z) / (tile_length * 0.41) + 0.37;
    let b = sample_surface(b_uv_x * tile_length, b_uv_z * tile_length);
    let rip = sample_ripple(x, z);
    return a.x + 0.10 * 0.41 * b.x + rip.x;
}

// (slope x, slope z, variance).
fn wave_slope(x: f32, z: f32, dist: f32, foot: vec4<f32>) -> vec3<f32> {
    let dpx_x = foot.x;
    let dpx_z = foot.y;
    let dpy_x = foot.z;
    let dpy_z = foot.w;
    let tile_length = mf(16u);
    let a = sample_surface_filtered(
        x, z, dpx_x / tile_length, dpx_z / tile_length, dpy_x / tile_length, dpy_z / tile_length, true,
    );
    let tile = tile_length * 0.41;
    let b_uv_x = (0.8 * x + 0.6 * z) / tile + 0.37;
    let b_uv_z = (-0.6 * x + 0.8 * z) / tile + 0.37;
    let b = sample_surface_filtered(
        b_uv_x * tile_length,
        b_uv_z * tile_length,
        (0.8 * dpx_x + 0.6 * dpx_z) / tile,
        (-0.6 * dpx_x + 0.8 * dpx_z) / tile,
        (0.8 * dpy_x + 0.6 * dpy_z) / tile,
        (-0.6 * dpy_x + 0.8 * dpy_z) / tile,
        true,
    );
    let rip = sample_ripple(x, z);
    var sx = a.y + 0.10 * (0.8 * b.y + 0.6 * b.z) + rip.y;
    var sz = a.z + 0.10 * (-0.6 * b.y + 0.8 * b.z) + rip.z;
    let detail_tile = tile_length * 0.13;
    let c_uv_x = (0.28 * x - 0.96 * z) / detail_tile + 0.71;
    let c_uv_z = (0.96 * x + 0.28 * z) / detail_tile + 0.71;
    let c = sample_surface_filtered(
        c_uv_x * tile_length,
        c_uv_z * tile_length,
        (0.28 * dpx_x - 0.96 * dpx_z) / detail_tile,
        (0.96 * dpx_x + 0.28 * dpx_z) / detail_tile,
        (0.28 * dpy_x - 0.96 * dpy_z) / detail_tile,
        (0.96 * dpy_x + 0.28 * dpy_z) / detail_tile,
        false,
    );
    let detail = 0.13 * exp(-dist * 0.18);
    sx += detail * (0.28 * c.y + 0.96 * c.z);
    sz += detail * (-0.96 * c.y + 0.28 * c.z);
    let variance = slope_variance(a) + 0.01 * slope_variance(b);
    return vec3<f32>(sx, sz, variance);
}

fn specks(
    color: vec3<f32>, x: f32, z: f32, ray: vec3<f32>, travel: f32, clock: f32, sun_light: vec3<f32>,
) -> vec3<f32> {
    var result = color;
    for (var k = 0; k < 3; k++) {
        let kf = f32(k);
        let dz = 0.22 + 0.38 * kf;
        var denom = -ray.y;
        if (denom < 0.05) {
            denom = 0.05;
        }
        let tt = dz / denom;
        let qx = (x + ray.x * tt) * 48.0 + clock * (0.05 + 0.03 * kf) + kf * 17.0;
        let qz = (z + ray.z * tt) * 48.0 + clock * 0.02 + kf * 17.0;
        let ix = floor(qx);
        let iz = floor(qz);
        let fx = qx - ix - 0.5;
        let fz = qz - iz - 0.5;
        let chance = hash12(ix + kf * 13.1, iz);
        let ox = hash12(ix + 3.1, iz) - 0.5;
        let oz = hash12(ix, iz + 7.7) - 0.5;
        let d = sqrt((fx - ox * 0.6) * (fx - ox * 0.6) + (fz - oz * 0.6) * (fz - oz * 0.6));
        if (chance > 0.988 && d < 0.10 && tt <= travel) {
            var tint = vec3<f32>(0.9, 1.0, 0.95);
            if (chance > 0.992) {
                tint = vec3<f32>(0.4, 0.35, 0.3);
            }
            let gain = exp(-0.074 * tt * 2.0) * 0.022;
            result = result + tint * gain * sun_light.x;
        }
    }
    return result;
}

fn underwater(
    x: f32, z: f32, height: f32, wd: vec3<f32>, normal: vec3<f32>, sun: vec3<f32>,
    clock: f32, foot: vec4<f32>, camera_t: f32,
) -> vec3<f32> {
    let dpx_x = foot.x;
    let dpx_z = foot.y;
    let dpy_x = foot.z;
    let dpy_z = foot.w;
    // Air into water cannot totally reflect, and a downward view stays downward.
    let ray = refract_(wd, normal, 1.0 / IOR);
    var bed_x = x;
    var bed_z = z;
    var travel = 0.0;
    for (var i = 0; i < 2; i++) {
        let depth = floor_depth(bed_x, bed_z);
        travel = (-depth - height) / ray.y;
        if (travel < 0.0) {
            travel = 0.0;
        }
        bed_x = x + ray.x * travel;
        bed_z = z + ray.z * travel;
    }
    var span = camera_t;
    if (span < 0.05) {
        span = 0.05;
    }
    span = (span + travel) / span;
    let bed = bed_color(bed_x, bed_z, dpx_x * span, dpx_z * span, dpy_x * span, dpy_z * span);
    let sun_ray = refracted_sun(sun);
    let ts = 1.0 - fresnel(sun.y, IOR);
    var column = height - (-floor_depth(bed_x, bed_z));
    if (column < 0.0) {
        column = 0.0;
    }
    let nudge = (bed.height - 0.35) * 0.05 / -sun_ray.y;
    let caustic_patch = mf(20u);
    let cu = (bed_x - mf(21u) + sun_ray.x * nudge) / caustic_patch;
    let cv = (bed_z - mf(22u) + sun_ray.z * nudge) / caustic_patch;
    var caus = caustic_grad(
        cu,
        cv,
        dpx_x * span / caustic_patch,
        dpx_z * span / caustic_patch,
        dpy_x * span / caustic_patch,
        dpy_z * span / caustic_patch,
    );
    let entered = sample_ripple(
        bed_x - sun_ray.x * column / -sun_ray.y,
        bed_z - sun_ray.z * column / -sun_ray.y,
    );
    var focus = 1.0 / (1.0 + 0.12 * column * entered.w);
    if (focus < 0.45) {
        focus = 0.45;
    }
    if (focus > 3.0) {
        focus = 3.0;
    }
    caus = caus * focus;
    let sig_a = vec3<f32>(0.40, 0.074, 0.088);
    let sig_s = vec3<f32>(0.028, 0.052, 0.068);
    let sig_t = sig_a + sig_s;
    // The refracted sun determines the path length through the water.
    let sun_t_y = sun_ray.y;
    let absorb = exp3(sig_t * (column / -sun_t_y));
    let ao = 0.55 + 0.45 * smooth_step(0.08, 0.42, bed.height);
    let sun_rgb = vec3<f32>(1.0, 0.90, 0.74) * 6.0;
    let sun_light = sun_rgb * ts;
    let esun = vec3<f32>(
        sun_light.x * absorb.x * caus.x * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.y * absorb.y * caus.y * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.z * absorb.z * caus.z * (-sun_t_y) * (0.75 + 0.25 * ao),
    );
    let sky_irr = vec3<f32>(0.62, 0.70, 0.78) * (PI * 0.22);
    let sky_abs = exp3((sig_a + sig_s * 0.4) * (column * 1.25));
    let esky = vec3<f32>(sky_irr.x * sky_abs.x * ao, sky_irr.y * sky_abs.y * ao, sky_irr.z * sky_abs.z * ao);
    let floor_l = vec3<f32>(
        bed.rgb.x / PI * (esun.x + esky.x),
        bed.rgb.y / PI * (esun.y + esky.y),
        bed.rgb.z / PI * (esun.z + esky.z),
    );
    let view_abs = exp3(sig_t * travel);
    let cos_s = sun_ray.x * (-ray.x) + sun_ray.y * (-ray.y) + sun_ray.z * (-ray.z);
    let g = 0.8;
    let phase = (1.0 - g * g) / (4.0 * PI * pow(1.0 + g * g - 2.0 * g * cos_s, 1.5));
    let mid_abs = exp3(sig_t * (column * 0.5 / -sun_t_y));
    let sky_mid = exp3(sig_a * (column * 0.6));
    let mid = vec3<f32>(
        sun_light.x * mid_abs.x * (phase + 0.02) + sky_irr.x * sky_mid.x / (4.0 * PI),
        sun_light.y * mid_abs.y * (phase + 0.02) + sky_irr.y * sky_mid.y / (4.0 * PI),
        sun_light.z * mid_abs.z * (phase + 0.02) + sky_irr.z * sky_mid.z / (4.0 * PI),
    );
    let scatter = vec3<f32>(
        sig_s.x / sig_t.x * mid.x * (1.0 - view_abs.x) * 3.2,
        sig_s.y / sig_t.y * mid.y * (1.0 - view_abs.y) * 3.2,
        sig_s.z / sig_t.z * mid.z * (1.0 - view_abs.z) * 3.2,
    );
    let color = vec3<f32>(
        floor_l.x * view_abs.x + scatter.x,
        floor_l.y * view_abs.y + scatter.y,
        floor_l.z * view_abs.z + scatter.z,
    );
    return specks(color, x, z, ray, travel, clock, sun_light);
}

fn lit_radiance(
    lk: Look, ndc_x: f32, ndc_y: f32, aspect: f32, pixel_x: f32, pixel_y: f32,
    sun: vec3<f32>, clock: f32,
) -> vec3<f32> {
    let rd = view_ray(lk, ndc_x, ndc_y, aspect);
    // Three fixed-point steps from the flat plane onto the waves.
    var wdy = rd.y;
    if (wdy > -0.0015) {
        wdy = -0.0015;
    }
    let wd = unit(vec3<f32>(rd.x, wdy, rd.z));
    var t = -lk.p.y / wd.y;
    var hit_x = 0.0;
    var hit_z = 0.0;
    var height = 0.0;
    for (var s = 0; s < 3; s++) {
        hit_x = lk.p.x + wd.x * t;
        hit_z = lk.p.z + wd.z * t;
        height = wave_height(hit_x, hit_z);
        t = (height - lk.p.y) / wd.y;
    }
    let foot = footprint(lk, ndc_x, ndc_y, aspect, height, pixel_x, pixel_y);
    let slope = wave_slope(hit_x, hit_z, t, foot);
    var normal = unit(vec3<f32>(-slope.x, 1.0, -slope.y));
    let v = -wd;
    var nv = dot3(normal, v);
    if (nv < 0.02) {
        normal = unit(vec3<f32>(
            normal.x + v.x * (0.02 - nv),
            normal.y + v.y * (0.02 - nv),
            normal.z + v.z * (0.02 - nv),
        ));
        nv = dot3(normal, v);
    }
    let f = fresnel(nv, IOR);
    let incident_dot = dot3(normal, wd);
    var reflected = vec3<f32>(
        wd.x - 2.0 * incident_dot * normal.x,
        wd.y - 2.0 * incident_dot * normal.y,
        wd.z - 2.0 * incident_dot * normal.z,
    );
    if (reflected.y < 0.0) {
        reflected = vec3<f32>(reflected.x, -reflected.y, reflected.z);
    }
    let sky = sky_radiance(reflected, sun);
    let refl = sky * 1.25;
    let variance = slope.z;
    let alpha2 = 0.00012 + 1.2 * variance;
    let half_v = unit(vec3<f32>(v.x + sun.x, v.y + sun.y, v.z + sun.z));
    var nh = dot3(normal, half_v);
    var nl = dot3(normal, sun);
    if (nh < 0.0) {
        nh = 0.0;
    }
    if (nl < 0.0) {
        nl = 0.0;
    }
    let dist = beckmann(nh, alpha2);
    let vis = smith_visibility(nl, nv, alpha2);
    let fh = fresnel(max(dot3(half_v, v), 0.0), IOR);
    let spec = dist * vis * fh * nl;
    let sun_rgb = vec3<f32>(1.0, 0.90, 0.74) * (6.0 * spec);
    let under = underwater(hit_x, hit_z, height, wd, normal, sun, clock, foot, t);
    var color = vec3<f32>(
        f * refl.x + (1.0 - f) * under.x + sun_rgb.x,
        f * refl.y + (1.0 - f) * under.y + sun_rgb.y,
        f * refl.z + (1.0 - f) * under.z + sun_rgb.z,
    );
    let haze = 1.0 - exp(-t * 0.004);
    let flat_ = unit(vec3<f32>(wd.x, 0.0, wd.z));
    var muh = flat_.x * sun.x + flat_.z * sun.z;
    if (muh < 0.0) {
        muh = 0.0;
    }
    let haze_c = vec3<f32>(0.60, 0.71, 0.82)
        + vec3<f32>(1.0, 0.86, 0.66) * (0.22 * pow(muh, 6.0) + 0.3 * pow(muh, 64.0));
    let haze_w = haze * 0.8;
    color = vec3<f32>(
        color.x + (haze_c.x * 0.95 - color.x) * haze_w,
        color.y + (haze_c.y * 0.95 - color.y) * haze_w,
        color.z + (haze_c.z * 0.95 - color.z) * haze_w,
    );
    var above = sky_radiance(rd, sun);
    let mu = rd.x * sun.x + rd.y * sun.y + rd.z * sun.z;
    let disc = smooth_step(0.99996, 0.999985, mu) * 18.0;
    above = above + vec3<f32>(1.0, 0.90, 0.74) * (6.0 * disc);
    let horizon = smooth_step(-0.0005, 0.0015, rd.y);
    return vec3<f32>(
        color.x + (above.x - color.x) * horizon,
        color.y + (above.y - color.y) * horizon,
        color.z + (above.z - color.z) * horizon,
    );
}

// ---------------------------------------------------------------------------
// The post passes: post.mojo and grade_pixel in frame.mojo.

fn radiance_at(x: i32, y: i32, width: i32) -> vec3<f32> {
    let p = u32((y * width + x) * 3);
    return vec3<f32>(radiance[p], radiance[p + 1u], radiance[p + 2u]);
}

// The part of the 3 by 3 mean of the radiance that is brighter than a limit.
fn highlight_texel(x: i32, y: i32, threshold: f32, scale: f32) -> vec3<f32> {
    let width = i32(frame_words[M_WIDTH]);
    let height = i32(frame_words[M_HEIGHT]);
    var sum = vec3<f32>(0.0);
    var count = 0.0;
    for (var oy = -1; oy < 2; oy++) {
        for (var ox = -1; ox < 2; ox++) {
            let sx = x + ox;
            let sy = y + oy;
            if (sx >= 0 && sy >= 0 && sx < width && sy < height) {
                sum = sum + radiance_at(sx, sy, width);
                count += 1.0;
            }
        }
    }
    sum = sum / count;
    let l = max(sum.x, max(sum.y, sum.z));
    var k = l - threshold;
    if (k < 0.0) {
        k = 0.0;
    }
    k /= max(l, 1e-4);
    return vec3<f32>((sum.x * k) * scale, (sum.y * k) * scale, (sum.z * k) * scale);
}

fn tap_offset(tap: i32) -> i32 {
    if (tap == 0) {
        return 0;
    }
    if (tap == 1) {
        return 1;
    }
    if (tap == 2) {
        return -1;
    }
    if (tap == 3) {
        return 3;
    }
    return -3;
}

fn tap_weight(tap: i32) -> f32 {
    if (tap == 0) {
        return 0.2270270270;
    }
    if (tap == 1 || tap == 2) {
        return 0.3162162162;
    }
    return 0.0702702703;
}

fn blur_texel(source_b: bool, x: i32, y: i32, horizontal: bool) -> vec3<f32> {
    let width = i32(frame_words[M_WIDTH]);
    let height = i32(frame_words[M_HEIGHT]);
    var sum = vec3<f32>(0.0);
    for (var tap = 0; tap < 5; tap++) {
        var sx = x;
        var sy = y;
        if (horizontal) {
            sx = x + tap_offset(tap);
        } else {
            sy = y + tap_offset(tap);
        }
        sx = clamp(sx, 0, width - 1);
        sy = clamp(sy, 0, height - 1);
        let p = u32((sy * width + sx) * 3);
        var texel = vec3<f32>(bloom_a[p], bloom_a[p + 1u], bloom_a[p + 2u]);
        if (source_b) {
            texel = vec3<f32>(bloom_b[p], bloom_b[p + 1u], bloom_b[p + 2u]);
        }
        sum = sum + texel * tap_weight(tap);
    }
    return sum;
}

fn fract_time(clock: f32) -> f32 {
    let t = clock * 7.13;
    return t - floor(t);
}

fn grade_pixel(
    rgb: vec3<f32>, glare: vec3<f32>, bloom: vec3<f32>, x: u32, y: u32, width: u32, height: u32,
    clock: f32,
) -> vec3<f32> {
    var cr = rgb.x;
    var cg = rgb.y;
    var cb = rgb.z;
    cr += glare.x * 0.9 * 1000.0;
    cg += glare.y * 0.9 * 1000.0;
    cb += glare.z * 0.9 * 1000.0;
    cr += bloom.x * 0.035;
    cg += bloom.y * 0.035;
    cb += bloom.z * 0.035;
    cr *= 0.63;
    cg *= 0.63;
    cb *= 0.63;
    let u = (f32(x) + 0.5) / f32(width) - 0.5;
    let v = (f32(y) + 0.5) / f32(height) - 0.5;
    let vig = 1.0 - 0.22 * (u * u + (v * 0.8) * (v * 0.8)) * 2.2;
    cr *= vig;
    cg *= vig;
    cb *= vig;
    cr = aces_channel(cr);
    cg = aces_channel(cg);
    cb = aces_channel(cb);
    let lum = cr * 0.2126 + cg * 0.7152 + cb * 0.0722;
    cr = lum + (cr - lum) * 0.90;
    cg = lum + (cg - lum) * 0.90;
    cb = lum + (cb - lum) * 0.90;
    let shadow = 1.0 - smooth_step(0.0, 0.35, lum);
    cr = cr + (cr * 0.96 - cr) * shadow;
    cg = cg + (cg * 1.0 - cg) * shadow;
    cb = cb + (cb * 1.05 - cb) * shadow;
    let gamma = 0.45454545;
    cr = pow(max(cr, 0.0), gamma);
    cg = pow(max(cg, 0.0), gamma);
    cb = pow(max(cb, 0.0), gamma);
    let grain = hash12(f32(x) + fract_time(clock) * 917.0, f32(y)) - 0.5;
    let amp = 0.018 * (1.0 - cr * 0.6);
    return vec3<f32>(cr + grain * amp, cg + grain * amp, cb + grain * amp);
}

// A channel in 0 to 1 as a rounded, clamped byte.
fn to_byte(value: f32) -> f32 {
    let scaled = clamp01(value) * 255.0 + 0.5;
    if (scaled <= 0.0) {
        return 0.0;
    }
    if (scaled >= 255.0) {
        return 255.0;
    }
    return floor(scaled);
}

// ---------------------------------------------------------------------------
// The entry points.

@compute @workgroup_size(8, 8)
fn shade(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = frame_words[M_WIDTH];
    let height = frame_words[M_HEIGHT];
    // The grid is whole groups, so its edges overhang the image.
    if (id.x >= width || id.y >= height) {
        return;
    }
    let w = f32(width);
    let h = f32(height);
    let ndc_x = ((f32(id.x) + 0.5) / w) * 2.0 - 1.0;
    let ndc_y = 1.0 - ((f32(id.y) + 0.5) / h) * 2.0;
    let sun = vec3<f32>(mf(12u), mf(13u), mf(14u));
    let rgb = lit_radiance(camera_look(), ndc_x, ndc_y, w / h, 2.0 / w, 2.0 / h, sun, mf(15u));
    let at = (id.y * width + id.x) * 3u;
    radiance[at] = rgb.x;
    radiance[at + 1u] = rgb.y;
    radiance[at + 2u] = rgb.z;
}

// One thread a point of the glare grid, which samples the highlight image
// (glare_sample_x and glare_sample_y in glare.mojo).
@compute @workgroup_size(8, 8)
fn sparks(@builtin(global_invocation_id) id: vec3<u32>) {
    let sw = frame_words[M_GRID_WIDTH];
    let sh = frame_words[M_GRID_HEIGHT];
    if (id.x >= sw || id.y >= sh) {
        return;
    }
    let width = f32(frame_words[M_WIDTH]);
    let height = f32(frame_words[M_HEIGHT]);
    let u = (f32(id.x) + 0.5) / f32(sw);
    let v = (f32(id.y) + 0.5) / f32(sh);
    let rgb = highlight_texel(i32(u * width), i32(v * height), 14.0, 0.001);
    let at = (id.y * sw + id.x) * 3u;
    samples[at] = rgb.x;
    samples[at + 1u] = rgb.y;
    samples[at + 2u] = rgb.z;
}

@compute @workgroup_size(8, 8)
fn bright(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = frame_words[M_WIDTH];
    if (id.x >= width || id.y >= frame_words[M_HEIGHT]) {
        return;
    }
    let rgb = highlight_texel(i32(id.x), i32(id.y), 2.5, 1.0);
    let at = (id.y * width + id.x) * 3u;
    bloom_a[at] = rgb.x;
    bloom_a[at + 1u] = rgb.y;
    bloom_a[at + 2u] = rgb.z;
}

@compute @workgroup_size(8, 8)
fn blur_h(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = frame_words[M_WIDTH];
    if (id.x >= width || id.y >= frame_words[M_HEIGHT]) {
        return;
    }
    let rgb = blur_texel(false, i32(id.x), i32(id.y), true);
    let at = (id.y * width + id.x) * 3u;
    bloom_b[at] = rgb.x;
    bloom_b[at + 1u] = rgb.y;
    bloom_b[at + 2u] = rgb.z;
}

@compute @workgroup_size(8, 8)
fn blur_v(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = frame_words[M_WIDTH];
    if (id.x >= width || id.y >= frame_words[M_HEIGHT]) {
        return;
    }
    let rgb = blur_texel(true, i32(id.x), i32(id.y), false);
    let at = (id.y * width + id.x) * 3u;
    bloom_a[at] = rgb.x;
    bloom_a[at + 1u] = rgb.y;
    bloom_a[at + 2u] = rgb.z;
}

@compute @workgroup_size(8, 8)
fn grade(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = frame_words[M_WIDTH];
    let height = frame_words[M_HEIGHT];
    if (id.x >= width || id.y >= height) {
        return;
    }
    let sw = frame_words[M_GRID_WIDTH];
    let sh = frame_words[M_GRID_HEIGHT];
    let p = (id.y * width + id.x) * 3u;
    // The glare grid cell of this pixel (glare_cell_x and glare_cell_y).
    let cell_x = u32(f32(id.x) / f32(width) * f32(sw));
    let cell_y = u32(f32(id.y) / f32(height) * f32(sh));
    let g = (cell_y * sw + cell_x) * 3u;
    let rgb = grade_pixel(
        vec3<f32>(radiance[p], radiance[p + 1u], radiance[p + 2u]),
        vec3<f32>(grid[g], grid[g + 1u], grid[g + 2u]),
        vec3<f32>(bloom_a[p], bloom_a[p + 1u], bloom_a[p + 2u]),
        id.x, id.y, width, height, mf(15u),
    );
    let bytes = vec4<f32>(to_byte(rgb.x), to_byte(rgb.y), to_byte(rgb.z), 255.0);
    textureStore(picture, vec2<i32>(i32(id.x), i32(id.y)), bytes / 255.0);
}

// ---------------------------------------------------------------------------
// The presentation: the picture on the canvas, scaled smoothly.

@group(0) @binding(0) var shown: texture_2d<f32>;
@group(0) @binding(1) var smoother: sampler;

struct Blit {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn blit_vertex(@builtin(vertex_index) index: u32) -> Blit {
    // One triangle that covers the screen.
    let corner = vec2<f32>(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Blit;
    out.position = vec4<f32>(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2<f32>(corner.x, 1.0 - corner.y);
    return out;
}

@fragment
fn blit_fragment(in: Blit) -> @location(0) vec4<f32> {
    return textureSample(shown, smoother, in.uv);
}
