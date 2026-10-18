// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The Gaussian splats of window/capi_splat.mojo, drawn by Metal.
//
// This is web/splat.wgsl in the Metal Shading Language, line for line, and it
// is render/splatrule.mojo, which is three.js's GaussianSplat vertex and
// fragment shaders. macos_splat.m compiles it when the window opens. Three
// passes draw a frame:
//
//   project  one thread for each splat, in draw order: the splat's center and
//            covariance go onto the screen, its spherical harmonics shade it,
//            and the result goes to `projected`.
//   vertex   one instance for each splat: a quad that reaches two standard
//            deviations out along the splat's axes.
//   fragment the opacity a * exp(-r^2 / 2), and a discard beyond r^2 = 4.
//
// The quads blend in the order that tm_splat_prepare sorted them, furthest
// first, with source-over and straight alpha, into a half-float picture. A last
// pass writes the picture to the window. The colors blend as the scan stores
// them, and the screen shows them unchanged, because the three.js example sets
// its working color space to sRGB.
//
// The view is 12 float4s, as the SPLAT_VIEW part of window/capi_abi.mojo lays
// out 48 floats: the model-view matrix, the projection matrix, then
// (width, height, eye.x, eye.y), (eye.z, degree, count, 0) and (background, 0).

#include <metal_stdlib>
using namespace metal;

constant float NEAREST_VIEW_Z = -0.01f;
constant float CLIP_XY = 1.4f;
constant float KERNEL_2D_SIZE = 0.3f;
constant float MAX_SPLAT_SIZE = 1024.0f;
constant float RADIUS_SQUARED = 4.0f;

struct View {
  float4 values[12];
};

static float4x4 model_view(constant View &view) {
  return float4x4(view.values[0], view.values[1], view.values[2], view.values[3]);
}

static float4x4 projection(constant View &view) {
  return float4x4(view.values[4], view.values[5], view.values[6], view.values[7]);
}

// One stored coefficient: (byte - 128) / 128.
static float coefficient(uint word, uint at) {
  return float((word >> ((at & 3u) * 8u)) & 255u) / 128.0f - 1.0f;
}

static float3 band(device const uint *words, uint at) {
  return float3(coefficient(words[at >> 2u], at),
                coefficient(words[(at + 1u) >> 2u], at + 1u),
                coefficient(words[(at + 2u) >> 2u], at + 2u));
}

// The view-dependent color of a splat: three.js's applySphericalHarmonics,
// bands one to three, for the unit direction from the camera to the splat.
static float3 harmonics(uint index, float3 d, uint degree, device const uint *sh1,
                        device const uint *sh2, device const uint *sh3) {
  float x = d.x;
  float y = d.y;
  float z = d.z;
  float3 rgb = float3(0.0f);
  uint at1 = index * 12u;
  rgb += band(sh1, at1) * (y * -0.4886025f);
  rgb += band(sh1, at1 + 3u) * (z * 0.4886025f);
  rgb += band(sh1, at1 + 6u) * (x * -0.4886025f);
  if (degree < 2u) {
    return rgb;
  }
  float xx = x * x;
  float yy = y * y;
  float zz = z * z;
  uint at2 = index * 16u;
  rgb += band(sh2, at2) * (x * y * 1.0925484f);
  rgb += band(sh2, at2 + 3u) * (y * z * -1.0925484f);
  rgb += band(sh2, at2 + 6u) * ((zz * 2.0f - xx - yy) * 0.3153915f);
  rgb += band(sh2, at2 + 9u) * (x * z * -1.0925484f);
  rgb += band(sh2, at2 + 12u) * ((xx - yy) * 0.5462742f);
  if (degree < 3u) {
    return rgb;
  }
  float xy = x * y;
  uint at3 = index * 24u;
  rgb += band(sh3, at3) * (y * (xx * 3.0f - yy) * -0.5900436f);
  rgb += band(sh3, at3 + 3u) * (xy * z * 2.8906114f);
  rgb += band(sh3, at3 + 6u) * (y * (zz * 4.0f - xx - yy) * -0.4570458f);
  rgb += band(sh3, at3 + 9u) * (z * (zz * 2.0f - xx * 3.0f - yy * 3.0f) * 0.3731763f);
  rgb += band(sh3, at3 + 12u) * (x * (zz * 4.0f - xx - yy) * -0.4570458f);
  rgb += band(sh3, at3 + 15u) * (z * (xx - yy) * 1.4453057f);
  rgb += band(sh3, at3 + 18u) * (x * (xx - yy * 3.0f) * -0.5900436f);
  return rgb;
}

static void hide(device float4 *projected, uint slot) {
  projected[slot] = float4(0.0f);
  projected[slot + 1u] = float4(0.0f);
  projected[slot + 2u] = float4(0.0f);
}

// Three float4s for each splat, in draw order: (x, y, axis.x, axis.y) in pixels
// with y down, (scale1, scale2, alpha, 0), and (r, g, b, 0).
kernel void project(constant View &view [[buffer(0)]],
                    device const float *centers [[buffer(1)]],
                    device const float *covariances [[buffer(2)]],
                    device const uint *colors [[buffer(3)]],
                    device const uint *sh1 [[buffer(4)]],
                    device const uint *sh2 [[buffer(5)]],
                    device const uint *sh3 [[buffer(6)]],
                    device const uint *order [[buffer(7)]],
                    device float4 *projected [[buffer(8)]],
                    uint position [[thread_position_in_grid]]) {
  uint count = uint(view.values[9].z);
  if (position >= count) {
    return;
  }
  uint slot = position * 3u;
  uint index = order[position];
  float3 center = float3(centers[index * 3u], centers[index * 3u + 1u], centers[index * 3u + 2u]);
  float4x4 m = model_view(view);
  float4x4 p = projection(view);
  float4 v = m * float4(center, 1.0f);
  float4 clip = p * v;
  float limit = clip.w * CLIP_XY;
  if (v.z >= NEAREST_VIEW_Z || clip.z < -clip.w || clip.z > clip.w) {
    hide(projected, slot);
    return;
  }
  if (clip.x < -limit || clip.x > limit || clip.y < -limit || clip.y > limit) {
    hide(projected, slot);
    return;
  }
  // The splat's covariance in view space, W C W^T, and on the screen.
  float3 r0 = float3(m[0].x, m[1].x, m[2].x);
  float3 r1 = float3(m[0].y, m[1].y, m[2].y);
  float3 r2 = float3(m[0].z, m[1].z, m[2].z);
  uint at = index * 6u;
  float3 cov0 = float3(covariances[at], covariances[at + 1u], covariances[at + 2u]);
  float3 cov1 = float3(covariances[at + 1u], covariances[at + 3u], covariances[at + 4u]);
  float3 cov2 = float3(covariances[at + 2u], covariances[at + 4u], covariances[at + 5u]);
  float3 vc0 = float3(dot(r0, cov0), dot(r0, cov1), dot(r0, cov2));
  float3 vc1 = float3(dot(r1, cov0), dot(r1, cov1), dot(r1, cov2));
  float3 vc2 = float3(dot(r2, cov0), dot(r2, cov1), dot(r2, cov2));
  float c00 = dot(vc0, r0);
  float c01 = dot(vc0, r1);
  float c02 = dot(vc0, r2);
  float c11 = dot(vc1, r1);
  float c12 = dot(vc1, r2);
  float c22 = dot(vc2, r2);
  float inv_z = 1.0f / min(v.z, NEAREST_VIEW_Z);
  float inv_z2 = inv_z * inv_z;
  float2 extent = view.values[8].xy;
  float fx = extent.x * 0.5f * p[0].x;
  float fy = extent.y * 0.5f * p[1].y;
  float j00 = -fx * inv_z;
  float j11 = -fy * inv_z;
  float j02 = fx * v.x * inv_z2;
  float j12 = fy * v.y * inv_z2;
  float a_base = j00 * j00 * c00 + j00 * j02 * c02 * 2.0f + j02 * j02 * c22;
  float b = j00 * j11 * c01 + j00 * j12 * c02 + j02 * j11 * c12 + (j02 * j12 * c22);
  float c_base = j11 * j11 * c11 + j11 * j12 * c12 * 2.0f + j12 * j12 * c22;
  // A low-pass filter of about a third of a pixel, and the opacity scaled so
  // that the wider splat is not brighter.
  float a = a_base + KERNEL_2D_SIZE;
  float c = c_base + KERNEL_2D_SIZE;
  float det_base = a_base * c_base - b * b;
  float det = a * c - b * b;
  float alpha_scale = sqrt(max(det_base / max(det, 0.000001f), 0.0f));
  float half_trace = (a + c) * 0.5f;
  float half_gap = (a - c) * 0.5f;
  float radius = sqrt(max(half_gap * half_gap + b * b, 0.0000001f));
  float lambda1 = max(half_trace + radius, 0.0000001f);
  float lambda2 = max(half_trace - radius, 0.0000001f);
  float angle = atan2(b * 2.0f, a - c) * 0.5f;

  uint packed = colors[index];
  float4 rgba = float4(float(packed & 255u), float((packed >> 8u) & 255u),
                       float((packed >> 16u) & 255u), float((packed >> 24u) & 255u)) /
                255.0f;
  uint degree = uint(view.values[9].y);
  if (degree > 0u) {
    float3 eye = float3(view.values[8].z, view.values[8].w, view.values[9].x);
    float3 toward = center - eye;
    float reach = length(toward);
    float3 d = float3(0.0f);
    if (reach > 0.0f) {
      d = toward / reach;
    }
    rgba = float4(rgba.rgb + harmonics(index, d, degree, sh1, sh2, sh3), rgba.a);
  }
  float3 rgb = clamp(rgba.rgb, float3(0.0f), float3(1.0f));
  projected[slot] = float4((clip.x / clip.w + 1.0f) * 0.5f * extent.x,
                           (1.0f - clip.y / clip.w) * 0.5f * extent.y, cos(angle), sin(angle));
  projected[slot + 1u] = float4(min(sqrt(lambda1), MAX_SPLAT_SIZE),
                                min(sqrt(lambda2), MAX_SPLAT_SIZE), rgba.a * alpha_scale, 0.0f);
  projected[slot + 2u] = float4(rgb, 0.0f);
}

struct Quad {
  float4 position [[position]];
  float2 offset;
  float4 color;
};

// A strip of four corners, (-2, -2), (2, -2), (-2, 2) and (2, 2), in standard
// deviations along the splat's two axes.
vertex Quad splat_vertex(uint corner [[vertex_id]], uint instance [[instance_id]],
                         constant View &view [[buffer(0)]],
                         device const float4 *quads [[buffer(1)]]) {
  uint at = instance * 3u;
  float4 place = quads[at];
  float4 shape = quads[at + 1u];
  float4 tint = quads[at + 2u];
  Quad result;
  // A splat that was hidden has no scale: put its quad outside the view.
  if (shape.z <= 0.0f) {
    result.position = float4(2.0f, 2.0f, 0.0f, 1.0f);
    result.offset = float2(0.0f);
    result.color = float4(0.0f);
    return result;
  }
  float u = float(corner & 1u) * 4.0f - 2.0f;
  float v = float(corner >> 1u) * 4.0f - 2.0f;
  // The offset in pixels with y up, along the axis and across it.
  float along = u * shape.x;
  float across = v * shape.y;
  float dx = place.z * along - place.w * across;
  float dy = place.w * along + place.z * across;
  float2 extent = view.values[8].xy;
  float2 pixel = float2(place.x + dx, place.y - dy);
  result.position =
      float4(pixel.x / extent.x * 2.0f - 1.0f, 1.0f - pixel.y / extent.y * 2.0f, 0.0f, 1.0f);
  result.offset = float2(u, v);
  result.color = float4(tint.rgb, shape.z);
  return result;
}

fragment float4 splat_fragment(Quad quad [[stage_in]]) {
  float r2 = dot(quad.offset, quad.offset);
  if (r2 > RADIUS_SQUARED) {
    discard_fragment();
  }
  return float4(quad.color.rgb, quad.color.a * exp(r2 * -0.5f));
}

// The picture on the window: one triangle that covers the view.
struct Screen {
  float4 position [[position]];
};

vertex Screen resolve_vertex(uint corner [[vertex_id]]) {
  Screen result;
  float x = float((corner << 1u) & 2u);
  float y = float(corner & 2u);
  result.position = float4(x * 2.0f - 1.0f, y * 2.0f - 1.0f, 0.0f, 1.0f);
  return result;
}

fragment float4 resolve_fragment(Screen screen [[stage_in]],
                                 texture2d<float, access::read> picture [[texture(0)]]) {
  uint2 pixel = uint2(screen.position.xy);
  return float4(clamp(picture.read(pixel).rgb, float3(0.0f), float3(1.0f)), 1.0f);
}
