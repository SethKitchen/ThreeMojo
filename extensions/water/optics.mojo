# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water optics in Clearwater's main shader.

Fresnel, refraction, Beckmann glints, absorption and the sky are the
page's formulae. `bed_color` repeats the pebble photograph the way the
shader does, then mixes sand, cobble and weed on top.
"""

from extensions.water.pebbles import (
    PebbleSample,
    PebbleTexels,
    sample_pebble_grad,
)
from math.arc_tangent import atan2_float32
from math.smoothstep import clamped_smoothstep, hermite_fade
from math.sine import fraction
from math.utils import mix_bilinear, mix_delta, saturate
from math.norm import squared_length2, squared_length3
from math.sine import sin_float32
from math.vector3 import Vector3, mix_delta3
from std.math import cos, exp, floor, fma, log, pow, sin, sqrt
from units.si import DEGREE, Angle


def water_ior() -> Float32:
    """Return the green-channel index of refraction, 1.3335.

    Returns:
        Clearwater's `IOR`.
    """
    return 1.3335


def channel_ior(channel: Int) -> Float32:
    """Return one dispersion index.

    Args:
        channel: 0 red, 1 green, 2 blue. Any other index returns green.

    Returns:
        The index Clearwater stores in `IORS`.
    """
    if channel == 0:
        return 1.3315
    if channel == 2:
        return 1.3365
    return 1.3335


def smoothstep(edge0: Float32, edge1: Float32, value: Float32) -> Float32:
    """Return Hermite interpolation between two edges.

    Args:
        edge0: The value that maps to 0.
        edge1: The value that maps to 1. It must not equal `edge0`.
        value: The sample.

    Returns:
        The smoothed step.
    """
    return clamped_smoothstep(edge0, edge1, value)


def hash12(x: Float32, y: Float32) -> Float32:
    """Return Clearwater's `hash12` at one point.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        A number in `[0, 1)`.
    """
    # The last `fract` reads the low bits of a product near 2e4. A fused
    # multiply-add there gives a different hash, and a CPU and a GPU fuse
    # differently. Each step is a Float32 operation rounded once.
    var c = Float32(0.1031)
    var k = Float32(33.33)
    var px = fraction(_times(x, c))
    var py = fraction(_times(y, c))
    var pz = fraction(_times(x, c))
    var dot = _plus(
        _plus(_times(px, _plus(py, k)), _times(py, _plus(pz, k))),
        _times(pz, _plus(px, k)),
    )
    px = _plus(px, dot)
    py = _plus(py, dot)
    pz = _plus(pz, dot)
    return fraction(_times(_plus(px, py), pz))


def _times(a: Float32, b: Float32) -> Float32:
    # An `fma` with a zero addend is the product rounded once, and no
    # compiler fuses its result into the next add. A plain product can fuse.
    # Apple GPUs have no Float64, so the rounding cannot go through one.
    return fma(a, b, Float32(0))


def _plus(a: Float32, b: Float32) -> Float32:
    # Each operand comes from `_times`, `_plus` or `_fract`, and none of
    # them is a plain product, so the sum cannot fuse. It rounds once.
    return a + b


def _sin(value: Float32) -> Float32:
    # A GPU sine is accurate near zero only, and Apple GPUs have no Float64
    # to reduce an angle in. The shared sine reduces in Float32 and integer
    # arithmetic, and gives the same bits on a CPU and a GPU.
    return sin_float32(value)


def value_noise(x: Float32, y: Float32) -> Float32:
    """Return one octave of value noise.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        Noise in `[0, 1]`.
    """
    var ix = floor(x)
    var iy = floor(y)
    var fx = x - ix
    var fy = y - iy
    var ux = hermite_fade(fx)
    var uy = hermite_fade(fy)
    return mix_bilinear(
        hash12(ix, iy),
        hash12(ix + 1.0, iy),
        hash12(ix, iy + 1.0),
        hash12(ix + 1.0, iy + 1.0),
        ux,
        uy,
    )


def fbm2(x: Float32, y: Float32) -> Float32:
    """Return four octaves of value noise, as the shader's `fbm2`.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        The summed noise.
    """
    var v = Float32(0.0)
    var a = Float32(0.5)
    var px = x
    var py = y
    for _octave in range(4):  # pragma: no branch
        v += a * value_noise(px, py)
        px = px * 2.03 + 17.1
        py = py * 2.03 + 17.1
        a *= 0.5
    return v


def fresnel(cos_i: Float32, ior: Float32) -> Float32:
    """Return the unpolarized dielectric Fresnel factor.

    Args:
        cos_i: Cosine of the incident angle, clamped to 0 and 1.
        ior: The index of refraction. Below 1 this can be total reflection.

    Returns:
        The reflected fraction, from 0 to 1.
    """
    var ci = saturate(cos_i)
    var st2 = (1.0 - ci * ci) / (ior * ior)
    if st2 >= 1.0:
        return 1.0
    var ct = sqrt(1.0 - st2)
    var rs = (ci - ior * ct) / (ci + ior * ct)
    var rp = (ior * ci - ct) / (ior * ci + ct)
    return 0.5 * squared_length2[DType.float32](rs, rp)


@fieldwise_init
struct Refracted(ImplicitlyCopyable):
    """A refraction, or a miss when the ray reflects totally."""

    var hit: Bool
    var x: Float32
    var y: Float32
    var z: Float32


def refract(
    ix: Float32,
    iy: Float32,
    iz: Float32,
    nx: Float32,
    ny: Float32,
    nz: Float32,
    eta: Float32,
) -> Refracted:
    """Refract a unit direction, using GLSL's `refract`.

    Args:
        ix: Incident x. The vector points along the ray.
        iy: Incident y.
        iz: Incident z.
        nx: Normal x. The normal is a unit vector.
        ny: Normal y.
        nz: Normal z.
        eta: Incident index over transmitted index.

    Returns:
        The refracted direction, or `hit` false on total internal reflection.
    """
    var cosi = nx * ix + ny * iy + nz * iz
    var k = 1.0 - eta * eta * (1.0 - cosi * cosi)
    if k < 0.0:
        return Refracted(False, 0.0, 0.0, 0.0)
    var scale = eta * cosi + sqrt(k)
    var bent = Vector3(ix, iy, iz) * eta - Vector3(nx, ny, nz) * scale
    return Refracted(True, bent.x, bent.y, bent.z)


def refracted_sun(sun: Vector3) -> Refracted:
    """Return the sun ray after it enters a horizontal water surface.

    Args:
        sun: Unit direction toward the sun, with positive y above water.

    Returns:
        The downward transmitted ray, including its horizontal offset.
    """
    return refract(-sun.x, -sun.y, -sun.z, 0.0, 1.0, 0.0, 1.0 / water_ior())


def beckmann(nh: Float32, alpha2: Float32) -> Float32:
    """Return the Beckmann distribution Clearwater uses for glints.

    Args:
        nh: Cosine of the angle between the normal and the half vector.
        alpha2: The squared roughness, including the LEAN variance term.

    Returns:
        `D`. A non-positive cosine or roughness returns 0.
    """
    if nh <= 0.0 or alpha2 <= 0.0:
        return 0.0
    var c2 = nh * nh
    if c2 < 1e-4:
        c2 = 1e-4
    var tan2 = (1.0 - c2) / c2
    var pi = Float32(3.141592653589793)
    return exp(-tan2 / alpha2) / (pi * alpha2 * c2 * c2)


def smith_visibility(nl: Float32, nv: Float32, alpha2: Float32) -> Float32:
    """Return the height-correlated visibility term in the glint.

    Args:
        nl: Cosine of the angle between the normal and the sun.
        nv: Cosine of the angle between the normal and the view.
        alpha2: The squared roughness.

    Returns:
        `Vis` from the shader.
    """
    return 0.5 / (
        nl * sqrt(nv * nv * (1.0 - alpha2) + alpha2)
        + nv * sqrt(nl * nl * (1.0 - alpha2) + alpha2)
        + 1e-5
    )


def aces_channel(value: Float32) -> Float32:
    """Return one channel through Clearwater's fitted ACES curve.

    Args:
        value: A linear channel. Negative light is treated as zero.

    Returns:
        The curve, clamped to 0 and 1.
    """
    var x = value
    if x < 0.0:
        x = 0.0
    var a = Float32(2.51)
    var b = Float32(0.03)
    var c = Float32(2.43)
    var d = Float32(0.59)
    var e = Float32(0.14)
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e))


def sun_direction() -> Vector3:
    """Return Clearwater's sun direction.

    Elevation is 31 degrees and azimuth is 6 degrees.

    Returns:
        A unit vector. Y is up.
    """
    var el = Angle(31.0, DEGREE).value
    var az = Angle(6.0, DEGREE).value
    var out = Vector3(
        sin(az) * cos(el),
        sin(el),
        -cos(az) * cos(el),
    )
    out.normalize()
    return out


def sky_radiance(
    dx: Float32, dy: Float32, dz: Float32, sun: Vector3
) -> Vector3:
    """Return the sky, including the distant headland.

    Args:
        dx: Direction x. It does not need to be a unit vector.
        dy: Direction y.
        dz: Direction z.
        sun: The unit sun direction.

    Returns:
        Linear radiance.
    """
    var length = sqrt(squared_length3[DType.float32](dx, dy, dz))
    var x = dx
    var y = dy
    var z = dz
    if length > 0.0:
        x /= length
        y /= length
        z /= length
    var mu = x * sun.x + y * sun.y + z * sun.z
    var zen = Vector3(0.11, 0.27, 0.62)
    var hor = Vector3(0.66, 0.78, 0.90)
    var t = pow(saturate(y), Float32(0.42))
    var color = mix_delta3(hor, zen, t)
    var glow = Float32(0.0)
    if mu > 0.0:
        glow = (
            0.22 * pow(mu, Float32(6))
            + 0.30 * pow(mu, Float32(64))
            + 1.6 * pow(mu, Float32(2400))
        )
    color = color + Vector3(1.0, 0.86, 0.66) * glow
    var azimuth = _atan2(z, x)
    var ridge = (
        0.040
        + 0.016 * _sin(azimuth * 2.0 + 0.7)
        + 0.011 * _sin(azimuth * 5.0 + 2.1)
        + 0.006 * _sin(azimuth * 11.0 + 0.3)
        + 0.003 * _sin(azimuth * 23.0 + 1.7)
    )
    ridge += 0.0045 * (value_noise(azimuth * 260.0, 0.0) - 0.5)
    ridge += 0.002 * (value_noise(azimuth * 900.0, 3.0) - 0.5)
    var hx = x
    var hz = z
    var hlen = sqrt(squared_length2[DType.float32](hx, hz))
    if hlen > 1e-5:
        hx /= hlen
        hz /= hlen
    var sx = sun.x
    var sz = sun.z
    var slen = sqrt(squared_length2[DType.float32](sx, sz))
    if slen > 1e-5:
        sx /= slen
        sz /= slen
    var back = smoothstep(-0.3, 0.95, hx * sx + hz * sz)
    # The ridge stays above about 0.007 for every azimuth, so the quotient is defined.
    var u = saturate(y / ridge)
    var tex = fbm2(azimuth * 420.0, y * 420.0)
    var pine = 0.045 * (0.6 + 0.8 * tex)
    var rock = 0.30 * (
        0.55 + 0.7 * fbm2(azimuth * 420.0 * 1.7 + 5.0, y * 420.0 * 1.7 + 5.0)
    )
    var cliff = smoothstep(0.42, 0.18, u + 0.25 * (tex - 0.5)) * smoothstep(
        0.35, 0.75, value_noise(azimuth * 18.0, 1.0)
    )
    var land_r = mix_delta(pine, rock, cliff)
    var land_g = (
        0.070 * (0.6 + 0.8 * tex)
        + (
            0.28 * (0.55 + 0.7 * fbm2(azimuth * 714.0 + 5.0, y * 714.0 + 5.0))
            - 0.070 * (0.6 + 0.8 * tex)
        )
        * cliff
    )
    var land_b = (
        0.042 * (0.6 + 0.8 * tex)
        + (
            0.23 * (0.55 + 0.7 * fbm2(azimuth * 714.0 + 5.0, y * 714.0 + 5.0))
            - 0.042 * (0.6 + 0.8 * tex)
        )
        * cliff
    )
    var shade = 1.0 + (0.45 - 1.0) * back
    land_r *= shade
    land_g *= shade
    land_b *= shade
    var aerial = 0.38 + 0.25 * back
    land_r = mix_delta(land_r, hor.x * 0.92, aerial)
    land_g = mix_delta(land_g, hor.y * 0.92, aerial)
    land_b = mix_delta(land_b, hor.z * 0.92, aerial)
    var cover = smoothstep(ridge + 2e-4, ridge - 2e-4, y)
    if y < -0.3:
        cover = 0.0
    return Vector3(
        mix_delta(color.x, land_r, cover),
        mix_delta(color.y, land_g, cover),
        mix_delta(color.z, land_b, cover),
    )


def _atan2(y: Float32, x: Float32) -> Float32:
    # libm's atan2 has no GPU form. The shared one keeps CPU and GPU equal.
    return atan2_float32(y, x)


def floor_depth(x: Float32, z: Float32) -> Float32:
    """Return how deep the shelving bed is, in meters.

    Args:
        x: World x. The shader's floor uses `xz.y` as this z.
        z: World z.

    Returns:
        A positive depth. The bed is `y = -depth`.
    """
    var shelf = -z + 1.5
    if shelf < 0.0:
        shelf = 0.0
    if shelf > 14.0:
        shelf = 14.0
    return (
        0.95
        + 0.17 * shelf
        + 0.30 * (value_noise(x * 0.22, z * 0.22) - 0.5)
        + 0.10 * (value_noise(x * 0.9 + 7.0, z * 0.9 + 7.0) - 0.5)
    )


@fieldwise_init
struct BedColor(ImplicitlyCopyable):
    """Albedo and a pseudo-height for one point on the bed."""

    var r: Float32
    var g: Float32
    var b: Float32
    var height: Float32


def bed_color[
    B: PebbleTexels
](
    bed: B,
    x: Float32,
    z: Float32,
    dx_x: Float32 = 0.0,
    dx_z: Float32 = 0.0,
    dy_x: Float32 = 0.0,
    dy_z: Float32 = 0.0,
) -> BedColor:
    """Return the seabed color at one point.

    Fine pebbles and coarse cobbles are two samplings of the photograph.
    Sand fills the gaps. A weed tint darkens the hollows. A non-zero
    footprint reads the photograph through its mipmaps.

    Parameters:
        B: The photograph storage.

    Args:
        bed: The pebble photograph, in linear light.
        x: World x, in meters.
        z: World z, in meters.
        dx_x: Change in x, in meters, for one pixel to the right.
        dx_z: Change in z, in meters, for one pixel to the right.
        dy_x: Change in x, in meters, for one pixel up.
        dy_z: Change in z, in meters, for one pixel up.

    Returns:
        Linear albedo and a height in about 0 to 1.
    """
    var fine = _pebbles(bed, x, z, 1.0, dx_x, dx_z, dy_x, dy_z)
    var coarse = _pebbles(
        bed,
        -z + 5.3,
        x + 5.3,
        1.7,
        -dx_z,
        dx_x,
        -dy_z,
        dy_x,
    )
    var mix_c = smoothstep(0.45, 0.62, fbm2(x * 0.21 + 40.0, z * 0.21 + 40.0))
    var rgb = mix_delta3(
        Vector3(fine.r, fine.g, fine.b),
        Vector3(coarse.r, coarse.g, coarse.b),
        mix_c,
    )
    var h = mix_delta(fine.height, coarse.height, mix_c)
    var zone = fbm2(x * 0.16 + 3.0, z * 0.16 + 3.0) + 0.10 * (
        value_noise(x * 2.5, z * 2.5) - 0.5
    )
    var marks = 0.5 + 0.5 * _sin(
        (x * 0.93 + z * 0.37) * 16.0 + 3.0 * value_noise(x * 0.8, z * 0.8)
    )
    var sand_n = 0.82 + 0.22 * value_noise(x * 40.0, z * 40.0) + 0.10 * marks
    var sand_r = 0.60 * sand_n
    var sand_g = 0.55 * sand_n
    var sand_b = 0.44 * sand_n
    sand_r = sand_r * sand_r * 1.4
    sand_g = sand_g * sand_g * 1.4
    sand_b = sand_b * sand_b * 1.4
    var sand_m = smoothstep(h + 0.02, h + 0.16, (zone - 0.46) * 1.6)
    rgb = mix_delta3(rgb, Vector3(sand_r, sand_g, sand_b), sand_m)
    h = mix_delta(h, 0.42 + 0.05 * marks, sand_m)
    var r = rgb.x
    var g = rgb.y
    var b = rgb.z
    var lum = r * 0.3 + g * 0.55 + b * 0.15
    r = lum + (r - lum) * 0.8
    g = lum + (g - lum) * 0.8
    b = lum + (b - lum) * 0.8
    r *= 1.10
    b *= 0.86
    var big = (
        value_noise(x * 0.45, z * 0.45) * 0.65
        + value_noise(x * 1.3 + 3.1, z * 1.3 + 3.1) * 0.35
    )
    var gain = 0.62 + (1.22 - 0.62) * big
    r *= gain
    g *= gain
    b *= gain
    var weed = smoothstep(
        0.55, 0.85, value_noise(x * 0.32 + 11.0, z * 0.32 + 11.0)
    )
    var weed_m = weed * 0.7
    r = r + (r * 0.55 - r) * weed_m
    g = g + (g * 0.62 - g) * weed_m
    b = b + (b * 0.40 - b) * weed_m
    var curve = Float32(1.2)
    r = (0.30 + (pow(max(r, 0.0), curve) - 0.30) * 0.72) * 0.6
    g = (0.29 + (pow(max(g, 0.0), curve) - 0.29) * 0.72) * 0.6
    b = (0.27 + (pow(max(b, 0.0), curve) - 0.27) * 0.72) * 0.6
    return BedColor(r, g, b, h)


def _pebbles[
    B: PebbleTexels
](
    bed: B,
    x: Float32,
    z: Float32,
    scale: Float32,
    dx_x: Float32,
    dx_z: Float32,
    dy_x: Float32,
    dy_z: Float32,
) -> BedColor:
    var meters = 0.78 * scale
    var uv_x = x / meters
    var uv_z = z / meters
    var du_dx = dx_x / meters
    var dv_dx = dx_z / meters
    var du_dy = dy_x / meters
    var dv_dy = dy_z / meters
    var level = value_noise(x * 0.85, z * 0.85) * 8.0
    var band = floor(level)
    var blend = level - band
    var shift_u = _sin(3.0 * band)
    var shift_v = _sin(7.0 * band)
    var first = sample_pebble_grad(
        bed, uv_x + shift_u, uv_z + shift_v, du_dx, dv_dx, du_dy, dv_dy
    )
    var next_band = band + 1.0
    var second = sample_pebble_grad(
        bed,
        uv_x + _sin(3.0 * next_band),
        uv_z + _sin(7.0 * next_band),
        du_dx,
        dv_dx,
        du_dy,
        dv_dy,
    )
    var delta = (
        (first.r - second.r) + (first.g - second.g) + (first.b - second.b)
    )
    var mix = smoothstep(0.2, 0.8, blend - 0.1 * delta)
    var color = first.mix(second, mix)
    # The page blurs the height lookup by six times the color footprint.
    var wide_a = sample_pebble_grad(
        bed,
        uv_x + shift_u,
        uv_z + shift_v,
        du_dx * 6.0,
        dv_dx * 6.0,
        du_dy * 6.0,
        dv_dy * 6.0,
    )
    var wide_b = sample_pebble_grad(
        bed,
        uv_x + _sin(3.0 * next_band),
        uv_z + _sin(7.0 * next_band),
        du_dx * 6.0,
        dv_dx * 6.0,
        du_dy * 6.0,
        dv_dy * 6.0,
    )
    var wide = wide_a.mix(wide_b, mix)
    var height = wide.r * 0.3 + wide.g * 0.55 + wide.b * 0.15
    return BedColor(color.r, color.g, color.b, height)


def max(a: Float32, b: Float32) -> Float32:
    """Return the larger of two floats.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        `a` when it is greater, otherwise `b`.
    """
    if a > b:
        return a
    return b
