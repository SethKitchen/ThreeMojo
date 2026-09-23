# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water optics in Clearwater's main shader.

Fresnel, refraction, Beckmann glints, absorption and the sky are the
page's formulae. The pebble photograph is not in this port. `bed_color`
keeps the same sand, cobble and weed mix and paints the stones from the
same hash the shader uses to hide a repeated tile.
"""

from math.vector3 import Vector3
from std.math import cos, exp, floor, log, pow, sin, sqrt
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


def clamp01(value: Float32) -> Float32:
    """Clamp `value` to the unit interval.

    Args:
        value: Any float.

    Returns:
        `value` limited to 0 and 1.
    """
    if value <= 0.0:
        return 0.0
    if value >= 1.0:
        return 1.0
    return value


def smoothstep(edge0: Float32, edge1: Float32, value: Float32) -> Float32:
    """Return Hermite interpolation between two edges.

    Args:
        edge0: The value that maps to 0.
        edge1: The value that maps to 1. It must not equal `edge0`.
        value: The sample.

    Returns:
        The smoothed step.
    """
    var t = clamp01((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def hash12(x: Float32, y: Float32) -> Float32:
    """Return Clearwater's `hash12` at one point.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        A number in `[0, 1)`.
    """
    var px = _fract(x * 0.1031)
    var py = _fract(y * 0.1031)
    var pz = _fract(x * 0.1031)
    var dot = px * (py + 33.33) + py * (pz + 33.33) + pz * (px + 33.33)
    px += dot
    py += dot
    pz += dot
    return _fract((px + py) * pz)


def _fract(value: Float32) -> Float32:
    return value - floor(value)


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
    var ux = fx * fx * (3.0 - 2.0 * fx)
    var uy = fy * fy * (3.0 - 2.0 * fy)
    var a = hash12(ix, iy)
    var b = hash12(ix + 1.0, iy)
    var c = hash12(ix, iy + 1.0)
    var d = hash12(ix + 1.0, iy + 1.0)
    var ab = a + (b - a) * ux
    var cd = c + (d - c) * ux
    return ab + (cd - ab) * uy


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
    var ci = clamp01(cos_i)
    var st2 = (1.0 - ci * ci) / (ior * ior)
    if st2 >= 1.0:
        return 1.0
    var ct = sqrt(1.0 - st2)
    var rs = (ci - ior * ct) / (ci + ior * ct)
    var rp = (ior * ci - ct) / (ior * ci + ct)
    return 0.5 * (rs * rs + rp * rp)


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
    return Refracted(
        True,
        eta * ix - scale * nx,
        eta * iy - scale * ny,
        eta * iz - scale * nz,
    )


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
    return clamp01((x * (a * x + b)) / (x * (c * x + d) + e))


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
    var length = sqrt(dx * dx + dy * dy + dz * dz)
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
    var t = pow(clamp01(y), Float32(0.42))
    var color = Vector3(
        hor.x + (zen.x - hor.x) * t,
        hor.y + (zen.y - hor.y) * t,
        hor.z + (zen.z - hor.z) * t,
    )
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
        + 0.016 * sin(azimuth * 2.0 + 0.7)
        + 0.011 * sin(azimuth * 5.0 + 2.1)
        + 0.006 * sin(azimuth * 11.0 + 0.3)
        + 0.003 * sin(azimuth * 23.0 + 1.7)
    )
    ridge += 0.0045 * (value_noise(azimuth * 260.0, 0.0) - 0.5)
    ridge += 0.002 * (value_noise(azimuth * 900.0, 3.0) - 0.5)
    var hx = x
    var hz = z
    var hlen = sqrt(hx * hx + hz * hz)
    if hlen > 1e-5:
        hx /= hlen
        hz /= hlen
    var sx = sun.x
    var sz = sun.z
    var slen = sqrt(sx * sx + sz * sz)
    if slen > 1e-5:
        sx /= slen
        sz /= slen
    var back = smoothstep(-0.3, 0.95, hx * sx + hz * sz)
    # The ridge stays above about 0.007 for every azimuth, so the quotient is defined.
    var u = clamp01(y / ridge)
    var tex = fbm2(azimuth * 420.0, y * 420.0)
    var pine = 0.045 * (0.6 + 0.8 * tex)
    var rock = 0.30 * (
        0.55 + 0.7 * fbm2(azimuth * 420.0 * 1.7 + 5.0, y * 420.0 * 1.7 + 5.0)
    )
    var cliff = smoothstep(0.42, 0.18, u + 0.25 * (tex - 0.5)) * smoothstep(
        0.35, 0.75, value_noise(azimuth * 18.0, 1.0)
    )
    var land_r = pine + (rock - pine) * cliff
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
    land_r = land_r + (hor.x * 0.92 - land_r) * aerial
    land_g = land_g + (hor.y * 0.92 - land_g) * aerial
    land_b = land_b + (hor.z * 0.92 - land_b) * aerial
    var cover = smoothstep(ridge + 2e-4, ridge - 2e-4, y)
    if y < -0.3:
        cover = 0.0
    return Vector3(
        color.x + (land_r - color.x) * cover,
        color.y + (land_g - color.y) * cover,
        color.z + (land_b - color.z) * cover,
    )


def _atan2(y: Float32, x: Float32) -> Float32:
    from std.math import atan2

    return atan2(y, x)


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


def bed_color(x: Float32, z: Float32) -> BedColor:
    """Return the seabed color at one point.

    The original page samples an embedded pebble photograph. This keeps the
    zone mix: fine stone, coarse cobble, sand in the gaps, and a weed tint.
    Stone color comes from `hash12`.

    Args:
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        Linear albedo and a height in about 0 to 1.
    """
    var fine = _stone(x, z, 1.0)
    var coarse = _stone(-z + 5.3, x, 1.7)
    var mix_c = smoothstep(0.45, 0.62, fbm2(x * 0.21 + 40.0, z * 0.21 + 40.0))
    var r = fine.r + (coarse.r - fine.r) * mix_c
    var g = fine.g + (coarse.g - fine.g) * mix_c
    var b = fine.b + (coarse.b - fine.b) * mix_c
    var h = fine.height + (coarse.height - fine.height) * mix_c
    var zone = fbm2(x * 0.16 + 3.0, z * 0.16 + 3.0) + 0.10 * (
        value_noise(x * 2.5, z * 2.5) - 0.5
    )
    var marks = 0.5 + 0.5 * sin(
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
    r = r + (sand_r - r) * sand_m
    g = g + (sand_g - g) * sand_m
    b = b + (sand_b - b) * sand_m
    h = h + (0.42 + 0.05 * marks - h) * sand_m
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


def _stone(x: Float32, z: Float32, scale: Float32) -> BedColor:
    var cell_x = floor(x / (0.78 * scale))
    var cell_z = floor(z / (0.78 * scale))
    var n = hash12(cell_x, cell_z)
    var m = hash12(cell_x + 3.1, cell_z + 7.7)
    var r = 0.35 + 0.40 * n
    var g = 0.32 + 0.38 * m
    var b = 0.28 + 0.30 * hash12(cell_z, cell_x)
    var h = 0.25 + 0.6 * n
    return BedColor(r, g, b, h)


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
