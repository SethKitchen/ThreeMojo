// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The Gaussian splats of window/capi_splat.mojo, drawn on a WebGPU device.
//
// This is render/splatrule.mojo, which is three.js's GaussianSplat vertex and
// fragment shaders, in WGSL. Three passes draw a frame:
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
// pass writes the picture to the canvas. The colors blend as the scan stores
// them, and the screen shows them unchanged, because the three.js example sets
// its working color space to sRGB.
//
// The view is 12 vec4s, as the SPLAT_VIEW part of window/capi_abi.mojo lays
// out 48 floats: the model-view matrix, the projection matrix, then
// (width, height, eye.x, eye.y), (eye.z, degree, count, 0) and (background, 0).

const NEAREST_VIEW_Z: f32 = -0.01;
const CLIP_XY: f32 = 1.4;
const KERNEL_2D_SIZE: f32 = 0.3;
const MAX_SPLAT_SIZE: f32 = 1024.0;
const RADIUS_SQUARED: f32 = 4.0;
const GROUP: u32 = 64u;

struct View {
  values: array<vec4<f32>, 12>,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> centers: array<f32>;
@group(0) @binding(2) var<storage, read> covariances: array<f32>;
@group(0) @binding(3) var<storage, read> colors: array<u32>;
@group(0) @binding(4) var<storage, read> sh1: array<u32>;
@group(0) @binding(5) var<storage, read> sh2: array<u32>;
@group(0) @binding(6) var<storage, read> sh3: array<u32>;
@group(0) @binding(7) var<storage, read> order: array<u32>;
// Three vec4s for each splat, in draw order: (x, y, axis.x, axis.y) in pixels
// with y down, (scale1, scale2, alpha, 0), and (r, g, b, 0). A vertex shader may
// only read a storage buffer, so the pass that draws binds the same buffer
// again, read only, as `quads`.
@group(0) @binding(8) var<storage, read_write> projected: array<vec4<f32>>;
@group(0) @binding(9) var<storage, read> quads: array<vec4<f32>>;

fn model_view() -> mat4x4<f32> {
  return mat4x4<f32>(view.values[0], view.values[1], view.values[2], view.values[3]);
}

fn projection() -> mat4x4<f32> {
  return mat4x4<f32>(view.values[4], view.values[5], view.values[6], view.values[7]);
}

fn size() -> vec2<f32> {
  return view.values[8].xy;
}

fn eye() -> vec3<f32> {
  return vec3<f32>(view.values[8].z, view.values[8].w, view.values[9].x);
}

fn degree() -> u32 {
  return u32(view.values[9].y);
}

fn count() -> u32 {
  return u32(view.values[9].z);
}

fn background() -> vec3<f32> {
  return view.values[10].xyz;
}

// One stored coefficient: (byte - 128) / 128.
fn coefficient(word: u32, at: u32) -> f32 {
  return f32((word >> ((at & 3u) * 8u)) & 255u) / 128.0 - 1.0;
}

fn sh1_color(index: u32, k: u32) -> vec3<f32> {
  let at = index * 12u + k * 3u;
  return vec3<f32>(
    coefficient(sh1[at >> 2u], at),
    coefficient(sh1[(at + 1u) >> 2u], at + 1u),
    coefficient(sh1[(at + 2u) >> 2u], at + 2u),
  );
}

fn sh2_color(index: u32, k: u32) -> vec3<f32> {
  let at = index * 16u + k * 3u;
  return vec3<f32>(
    coefficient(sh2[at >> 2u], at),
    coefficient(sh2[(at + 1u) >> 2u], at + 1u),
    coefficient(sh2[(at + 2u) >> 2u], at + 2u),
  );
}

fn sh3_color(index: u32, k: u32) -> vec3<f32> {
  let at = index * 24u + k * 3u;
  return vec3<f32>(
    coefficient(sh3[at >> 2u], at),
    coefficient(sh3[(at + 1u) >> 2u], at + 1u),
    coefficient(sh3[(at + 2u) >> 2u], at + 2u),
  );
}

// The view-dependent color of a splat: three.js's applySphericalHarmonics,
// bands one to three, for the unit direction from the camera to the splat.
fn harmonics(index: u32, d: vec3<f32>) -> vec3<f32> {
  let x = d.x;
  let y = d.y;
  let z = d.z;
  var rgb = vec3<f32>(0.0);
  rgb += sh1_color(index, 0u) * (y * -0.4886025);
  rgb += sh1_color(index, 1u) * (z * 0.4886025);
  rgb += sh1_color(index, 2u) * (x * -0.4886025);
  if (degree() < 2u) {
    return rgb;
  }
  let xx = x * x;
  let yy = y * y;
  let zz = z * z;
  rgb += sh2_color(index, 0u) * (x * y * 1.0925484);
  rgb += sh2_color(index, 1u) * (y * z * -1.0925484);
  rgb += sh2_color(index, 2u) * ((zz * 2.0 - xx - yy) * 0.3153915);
  rgb += sh2_color(index, 3u) * (x * z * -1.0925484);
  rgb += sh2_color(index, 4u) * ((xx - yy) * 0.5462742);
  if (degree() < 3u) {
    return rgb;
  }
  let xy = x * y;
  rgb += sh3_color(index, 0u) * (y * (xx * 3.0 - yy) * -0.5900436);
  rgb += sh3_color(index, 1u) * (xy * z * 2.8906114);
  rgb += sh3_color(index, 2u) * (y * (zz * 4.0 - xx - yy) * -0.4570458);
  rgb += sh3_color(index, 3u) * (z * (zz * 2.0 - xx * 3.0 - yy * 3.0) * 0.3731763);
  rgb += sh3_color(index, 4u) * (x * (zz * 4.0 - xx - yy) * -0.4570458);
  rgb += sh3_color(index, 5u) * (z * (xx - yy) * 1.4453057);
  rgb += sh3_color(index, 6u) * (x * (xx - yy * 3.0) * -0.5900436);
  return rgb;
}

fn hide(at: u32) {
  projected[at] = vec4<f32>(0.0);
  projected[at + 1u] = vec4<f32>(0.0);
  projected[at + 2u] = vec4<f32>(0.0);
}

@compute @workgroup_size(64)
fn project(@builtin(global_invocation_id) id: vec3<u32>) {
  let position = id.x;
  if (position >= count()) {
    return;
  }
  let slot = position * 3u;
  let index = order[position];
  let center = vec3<f32>(centers[index * 3u], centers[index * 3u + 1u], centers[index * 3u + 2u]);
  let m = model_view();
  let p = projection();
  let v = m * vec4<f32>(center, 1.0);
  let clip = p * v;
  let limit = clip.w * CLIP_XY;
  if (v.z >= NEAREST_VIEW_Z || clip.z < -clip.w || clip.z > clip.w) {
    hide(slot);
    return;
  }
  if (clip.x < -limit || clip.x > limit || clip.y < -limit || clip.y > limit) {
    hide(slot);
    return;
  }
  // The splat's covariance in view space, W C W^T, and on the screen.
  let r0 = vec3<f32>(m[0].x, m[1].x, m[2].x);
  let r1 = vec3<f32>(m[0].y, m[1].y, m[2].y);
  let r2 = vec3<f32>(m[0].z, m[1].z, m[2].z);
  let at = index * 6u;
  let cov0 = vec3<f32>(covariances[at], covariances[at + 1u], covariances[at + 2u]);
  let cov1 = vec3<f32>(covariances[at + 1u], covariances[at + 3u], covariances[at + 4u]);
  let cov2 = vec3<f32>(covariances[at + 2u], covariances[at + 4u], covariances[at + 5u]);
  let vc0 = vec3<f32>(dot(r0, cov0), dot(r0, cov1), dot(r0, cov2));
  let vc1 = vec3<f32>(dot(r1, cov0), dot(r1, cov1), dot(r1, cov2));
  let vc2 = vec3<f32>(dot(r2, cov0), dot(r2, cov1), dot(r2, cov2));
  let c00 = dot(vc0, r0);
  let c01 = dot(vc0, r1);
  let c02 = dot(vc0, r2);
  let c11 = dot(vc1, r1);
  let c12 = dot(vc1, r2);
  let c22 = dot(vc2, r2);
  let inv_z = 1.0 / min(v.z, NEAREST_VIEW_Z);
  let inv_z2 = inv_z * inv_z;
  let extent = size();
  let fx = extent.x * 0.5 * p[0].x;
  let fy = extent.y * 0.5 * p[1].y;
  let j00 = -fx * inv_z;
  let j11 = -fy * inv_z;
  let j02 = fx * v.x * inv_z2;
  let j12 = fy * v.y * inv_z2;
  let a_base = j00 * j00 * c00 + j00 * j02 * c02 * 2.0 + j02 * j02 * c22;
  let b = j00 * j11 * c01 + j00 * j12 * c02 + j02 * j11 * c12 + (j02 * j12 * c22);
  let c_base = j11 * j11 * c11 + j11 * j12 * c12 * 2.0 + j12 * j12 * c22;
  // A low-pass filter of about a third of a pixel, and the opacity scaled so
  // that the wider splat is not brighter.
  let a = a_base + KERNEL_2D_SIZE;
  let c = c_base + KERNEL_2D_SIZE;
  let det_base = a_base * c_base - b * b;
  let det = a * c - b * b;
  let alpha_scale = sqrt(max(det_base / max(det, 0.000001), 0.0));
  let half_trace = (a + c) * 0.5;
  let half_gap = (a - c) * 0.5;
  let radius = sqrt(max(half_gap * half_gap + b * b, 0.0000001));
  let lambda1 = max(half_trace + radius, 0.0000001);
  let lambda2 = max(half_trace - radius, 0.0000001);
  let angle = atan2(b * 2.0, a - c) * 0.5;

  let packed = colors[index];
  var rgba = vec4<f32>(
    f32(packed & 255u),
    f32((packed >> 8u) & 255u),
    f32((packed >> 16u) & 255u),
    f32((packed >> 24u) & 255u),
  ) / 255.0;
  if (degree() > 0u) {
    let toward = center - eye();
    let reach = length(toward);
    var d = vec3<f32>(0.0);
    if (reach > 0.0) {
      d = toward / reach;
    }
    rgba = vec4<f32>(rgba.rgb + harmonics(index, d), rgba.a);
  }
  let rgb = clamp(rgba.rgb, vec3<f32>(0.0), vec3<f32>(1.0));
  projected[slot] = vec4<f32>(
    (clip.x / clip.w + 1.0) * 0.5 * extent.x,
    (1.0 - clip.y / clip.w) * 0.5 * extent.y,
    cos(angle),
    sin(angle),
  );
  projected[slot + 1u] = vec4<f32>(
    min(sqrt(lambda1), MAX_SPLAT_SIZE),
    min(sqrt(lambda2), MAX_SPLAT_SIZE),
    rgba.a * alpha_scale,
    0.0,
  );
  projected[slot + 2u] = vec4<f32>(rgb, 0.0);
}

struct Quad {
  @builtin(position) position: vec4<f32>,
  @location(0) offset: vec2<f32>,
  @location(1) color: vec4<f32>,
}

// A strip of four corners, (-2, -2), (2, -2), (-2, 2) and (2, 2), in standard
// deviations along the splat's two axes.
@vertex
fn splat_vertex(@builtin(vertex_index) corner: u32, @builtin(instance_index) instance: u32) -> Quad {
  let at = instance * 3u;
  let place = quads[at];
  let shape = quads[at + 1u];
  let tint = quads[at + 2u];
  var result: Quad;
  // A splat that was hidden has no scale: put its quad outside the view.
  if (shape.z <= 0.0) {
    result.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
    result.offset = vec2<f32>(0.0);
    result.color = vec4<f32>(0.0);
    return result;
  }
  let u = f32(corner & 1u) * 4.0 - 2.0;
  let v = f32(corner >> 1u) * 4.0 - 2.0;
  // The offset in pixels with y up, along the axis and across it.
  let along = u * shape.x;
  let across = v * shape.y;
  let dx = place.z * along - place.w * across;
  let dy = place.w * along + place.z * across;
  let extent = size();
  let pixel = vec2<f32>(place.x + dx, place.y - dy);
  result.position = vec4<f32>(pixel.x / extent.x * 2.0 - 1.0, 1.0 - pixel.y / extent.y * 2.0, 0.0, 1.0);
  result.offset = vec2<f32>(u, v);
  result.color = vec4<f32>(tint.rgb, shape.z);
  return result;
}

@fragment
fn splat_fragment(quad: Quad) -> @location(0) vec4<f32> {
  let r2 = dot(quad.offset, quad.offset);
  if (r2 > RADIUS_SQUARED) {
    discard;
  }
  return vec4<f32>(quad.color.rgb, quad.color.a * exp(r2 * -0.5));
}

// The picture on the canvas: one triangle that covers the view.
struct Screen {
  @builtin(position) position: vec4<f32>,
}

@vertex
fn resolve_vertex(@builtin(vertex_index) corner: u32) -> Screen {
  var result: Screen;
  let x = f32((corner << 1u) & 2u);
  let y = f32(corner & 2u);
  result.position = vec4<f32>(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
  return result;
}

@group(0) @binding(10) var picture: texture_2d<f32>;

@fragment
fn resolve_fragment(screen: Screen) -> @location(0) vec4<f32> {
  let pixel = vec2<i32>(screen.position.xy);
  return vec4<f32>(clamp(textureLoad(picture, pixel, 0).rgb, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}
