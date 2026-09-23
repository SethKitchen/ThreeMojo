# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The height and slope grid the water shader samples.

`resolve_surface` is the resolve shader: height, `∂h/∂x`, `∂h/∂z`, and the
squared slope that LEAN mapping turns into a variance. Sampling repeats
across the patch. `sample_surface` is the page's bilinear `texture` call.
`sample_surface_smooth` is the cubic filter the page uses on slopes, so
highlights stay smooth. `sample_surface_filtered` is that sample with the
page's mipmaps and anisotropy of 8.
"""

from extensions.water.field import ComplexField, fft2
from extensions.water.filter import anisotropic_step
from extensions.water.resolution import SpectrumResolution
from extensions.water.spectrum import (
    build_spectrum,
    clearwater_patch,
    clearwater_slope,
    evolve_spectrum,
)
from std.math import floor
from units.si import SECOND, Duration, Length


@fieldwise_init
struct SurfaceSample(ImplicitlyCopyable):
    """One filtered sample of the ocean surface."""

    var height: Float32
    var slope_x: Float32
    var slope_z: Float32
    var slope_sq: Float32


struct SurfaceField(Copyable, Movable):
    """A resolved ocean surface on one square grid."""

    var patch: Length
    var field: ComplexField
    var mips: List[ComplexField]

    def __init__(out self, patch: Length, var field: ComplexField) raises:
        """Store a resolved grid and its mipmaps.

        Args:
            patch: The world length of one tile.
            field: Height, slopes and squared slope, four channels.

        Raises:
            Error: If a coarser mip cannot be allocated.
        """
        self.patch = patch
        self.field = field^
        self.mips = _mip_chain(self.field)


def resolve_surface(spatial: ComplexField) -> ComplexField:
    """Pack an inverse FFT into height, slopes and squared slope.

    Args:
        spatial: The grid after the ocean FFT. Channel 0 is height, channel
            1 is `∂h/∂x`, channel 2 is `∂h/∂z`.

    Returns:
        The surface texture. Channel 3 is the squared slope.
    """
    var out = spatial.copy()
    var n = spatial.n
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var h = spatial.channel(x, y, 0)
            var sx = spatial.channel(x, y, 1)
            var sz = spatial.channel(x, y, 2)
            out.put(x, y, 0, h)
            out.put(x, y, 1, sx)
            out.put(x, y, 2, sz)
            out.put(x, y, 3, sx * sx + sz * sz)
    return out^


def water_surface(
    resolution: SpectrumResolution,
    patch: Length,
    time: Duration,
    target_slope: Float32,
) raises -> SurfaceField:
    """Build, evolve and transform one ocean surface.

    Args:
        resolution: The spectrum grid. 256 matches Clearwater.
        patch: The patch length.
        time: Shader time `uT`, in seconds.
        target_slope: The root-mean-square slope the spectrum is scaled to.

    Returns:
        The resolved surface.

    Raises:
        Error: If a size, a length or the slope is not valid.
    """
    var spectrum = build_spectrum(resolution, patch, target_slope)
    var evolved = evolve_spectrum(spectrum, patch, time)
    var spatial = fft2(evolved, 1.0)
    return SurfaceField(patch, resolve_surface(spatial))


def clearwater_surface(time: Duration) raises -> SurfaceField:
    """Build the page's ocean at shader time `time`.

    The grid is 64 on a side rather than 256, so a still finishes in a
    software renderer. The spectrum, the patch and the slope match the page.

    Args:
        time: Shader time `uT`, in seconds.

    Returns:
        The resolved surface.

    Raises:
        Error: If the surface cannot be built.
    """
    return water_surface(
        SpectrumResolution(64),
        clearwater_patch(),
        time,
        clearwater_slope(),
    )


def _wrap(index: Int, n: Int) -> Int:
    # Mojo's remainder is non-negative, so a negative index already wraps.
    return index % n


def sample_surface(
    surface: SurfaceField, x: Float32, z: Float32
) -> SurfaceSample:
    """Sample the surface at one world position, repeating the patch.

    Args:
        surface: A resolved ocean.
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        The bilinear height and slopes. Variance for LEAN mapping is
        `slope_sq` minus the squared filtered slope, and it is not negative.
    """
    var n = surface.field.n
    var u = x / surface.patch.value
    var v = z / surface.patch.value
    var px = u * Float32(n)
    var pz = v * Float32(n)
    var x0 = Int(floor(px))
    var z0 = Int(floor(pz))
    var fx = px - Float32(x0)
    var fz = pz - Float32(z0)
    var x1 = _wrap(x0 + 1, n)
    var z1 = _wrap(z0 + 1, n)
    x0 = _wrap(x0, n)
    z0 = _wrap(z0, n)
    var s00 = _texel(surface.field, x0, z0)
    var s10 = _texel(surface.field, x1, z0)
    var s01 = _texel(surface.field, x0, z1)
    var s11 = _texel(surface.field, x1, z1)
    var a = _mix_sample(s00, s10, fx)
    var b = _mix_sample(s01, s11, fx)
    return _mix_sample(a, b, fz)


def sample_surface_smooth(
    surface: SurfaceField, x: Float32, z: Float32
) -> SurfaceSample:
    """Sample the surface with the page's cubic B-spline filter.

    Four bilinear taps. The page uses this on the two large tiles so a
    slope, and the sun glint on it, stays smooth.

    Args:
        surface: A resolved ocean.
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        The cubic height and slopes.
    """
    var n = Float32(surface.field.n)
    var patch = surface.patch.value
    var px = x / patch * n - 0.5
    var pz = z / patch * n - 0.5
    var ix = floor(px)
    var iz = floor(pz)
    var fx = px - ix
    var fz = pz - iz
    var fx2 = fx * fx
    var fz2 = fz * fz
    var fx3 = fx2 * fx
    var fz3 = fz2 * fz
    var wx0 = (-fx3 + 3.0 * fx2 - 3.0 * fx + 1.0) / 6.0
    var wz0 = (-fz3 + 3.0 * fz2 - 3.0 * fz + 1.0) / 6.0
    var wx1 = (3.0 * fx3 - 6.0 * fx2 + 4.0) / 6.0
    var wz1 = (3.0 * fz3 - 6.0 * fz2 + 4.0) / 6.0
    var wx2 = (-3.0 * fx3 + 3.0 * fx2 + 3.0 * fx + 1.0) / 6.0
    var wz2 = (-3.0 * fz3 + 3.0 * fz2 + 3.0 * fz + 1.0) / 6.0
    var wx3 = fx3 / 6.0
    var wz3 = fz3 / 6.0
    var gx0 = wx0 + wx1
    var gz0 = wz0 + wz1
    var gx1 = wx2 + wx3
    var gz1 = wz2 + wz3
    var h0x = (wx1 / gx0 - 0.5 + ix) / n * patch
    var h1x = (wx3 / gx1 + 1.5 + ix) / n * patch
    var h0z = (wz1 / gz0 - 0.5 + iz) / n * patch
    var h1z = (wz3 / gz1 + 1.5 + iz) / n * patch
    var s00 = sample_surface(surface, h0x, h0z)
    var s10 = sample_surface(surface, h1x, h0z)
    var s01 = sample_surface(surface, h0x, h1z)
    var s11 = sample_surface(surface, h1x, h1z)
    # The four taps use the cubic weights. They are not a unit mix.
    var top = _add_sample(_scale_sample(s00, gx0), _scale_sample(s10, gx1))
    var bottom = _add_sample(_scale_sample(s01, gx0), _scale_sample(s11, gx1))
    return _add_sample(_scale_sample(top, gz0), _scale_sample(bottom, gz1))


def _texel(field: ComplexField, x: Int, y: Int) -> SurfaceSample:
    return SurfaceSample(
        field.channel(x, y, 0),
        field.channel(x, y, 1),
        field.channel(x, y, 2),
        field.channel(x, y, 3),
    )


def _mix_sample(
    a: SurfaceSample, b: SurfaceSample, t: Float32
) -> SurfaceSample:
    var s = 1.0 - t
    return SurfaceSample(
        a.height * s + b.height * t,
        a.slope_x * s + b.slope_x * t,
        a.slope_z * s + b.slope_z * t,
        a.slope_sq * s + b.slope_sq * t,
    )


def _scale_sample(sample: SurfaceSample, weight: Float32) -> SurfaceSample:
    return SurfaceSample(
        sample.height * weight,
        sample.slope_x * weight,
        sample.slope_z * weight,
        sample.slope_sq * weight,
    )


def _add_sample(a: SurfaceSample, b: SurfaceSample) -> SurfaceSample:
    return SurfaceSample(
        a.height + b.height,
        a.slope_x + b.slope_x,
        a.slope_z + b.slope_z,
        a.slope_sq + b.slope_sq,
    )


def sample_surface_filtered(
    surface: SurfaceField,
    x: Float32,
    z: Float32,
    du_dx: Float32,
    dv_dx: Float32,
    du_dy: Float32,
    dv_dy: Float32,
    cubic: Bool,
) -> SurfaceSample:
    """Sample one ocean tile with the page's mipmaps.

    A footprint of one texel or less uses the cubic filter when `cubic` is
    true, and bilinear sampling otherwise. A wider footprint averages along
    its long axis. The level comes from the short axis.

    Args:
        surface: A resolved ocean.
        x: World x of this tile's texture coordinate, in meters.
        z: World z of this tile's texture coordinate, in meters.
        du_dx: Change in texture `u` for one pixel to the right.
        dv_dx: Change in texture `v` for one pixel to the right.
        du_dy: Change in texture `u` for one pixel up.
        dv_dy: Change in texture `v` for one pixel up.
        cubic: True uses the cubic filter on a one-texel footprint.

    Returns:
        The filtered height and slopes.
    """
    var step = anisotropic_step(
        du_dx,
        dv_dx,
        du_dy,
        dv_dy,
        Float32(surface.field.n),
        Float32(surface.field.n),
        8.0,
        0.0,
        Float32(len(surface.mips)),
    )
    var smooth = cubic
    if step.lod > 0.0:
        smooth = False
    if step.taps > 1:
        smooth = False
    if smooth:
        return sample_surface_smooth(surface, x, z)
    var u = x / surface.patch.value
    var v = z / surface.patch.value
    var acc = SurfaceSample(0.0, 0.0, 0.0, 0.0)
    var count = step.taps
    for i in range(count):  # pragma: no branch
        var o = (Float32(i) + 0.5) / Float32(count) - 0.5
        var sample = _trilinear_uv(
            surface, u + step.du * o, v + step.dv * o, step.lod
        )
        acc = _add_sample(acc, sample)
    return _scale_sample(acc, 1.0 / Float32(count))


def _trilinear_uv(
    surface: SurfaceField, u: Float32, v: Float32, lod: Float32
) -> SurfaceSample:
    var levels = len(surface.mips)
    var i0 = Int(floor(lod))
    var i1 = i0 + 1
    if i1 > levels:
        i1 = levels
    var frac = lod - Float32(i0)
    var a = _sample_level(surface, i0, u, v)
    var b = _sample_level(surface, i1, u, v)
    return _mix_sample(a, b, frac)


def _sample_level(
    surface: SurfaceField, level: Int, u: Float32, v: Float32
) -> SurfaceSample:
    if level <= 0:
        return _sample_uv(surface.field, u, v)
    return _sample_uv(surface.mips[level - 1], u, v)


def _sample_uv(field: ComplexField, u: Float32, v: Float32) -> SurfaceSample:
    var n = field.n
    var px = u * Float32(n)
    var pz = v * Float32(n)
    var x0 = Int(floor(px))
    var z0 = Int(floor(pz))
    var fx = px - Float32(x0)
    var fz = pz - Float32(z0)
    var x1 = _wrap(x0 + 1, n)
    var z1 = _wrap(z0 + 1, n)
    x0 = _wrap(x0, n)
    z0 = _wrap(z0, n)
    var s00 = _texel(field, x0, z0)
    var s10 = _texel(field, x1, z0)
    var s01 = _texel(field, x0, z1)
    var s11 = _texel(field, x1, z1)
    var a = _mix_sample(s00, s10, fx)
    var b = _mix_sample(s01, s11, fx)
    return _mix_sample(a, b, fz)


def _mip_chain(field: ComplexField) raises -> List[ComplexField]:
    var levels = List[ComplexField]()
    var side = field.n
    var current = field.copy()
    while side > 4:
        var next = _half_surface(current)
        side = next.n
        levels.append(next^)
        current = levels[len(levels) - 1].copy()
    return levels^


def _half_surface(source: ComplexField) raises -> ComplexField:
    var n = source.n // 2
    var out = ComplexField(SpectrumResolution(n))
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            for c in range(4):  # pragma: no branch
                var sum = (
                    source.channel(x * 2, y * 2, c)
                    + source.channel(x * 2 + 1, y * 2, c)
                    + source.channel(x * 2, y * 2 + 1, c)
                    + source.channel(x * 2 + 1, y * 2 + 1, c)
                )
                out.put(x, y, c, sum * 0.25)
    return out^


def slope_variance(sample: SurfaceSample) -> Float32:
    """Return the LEAN slope variance of one filtered sample.

    Args:
        sample: A bilinear sample. `slope_sq` is the filtered square, and
            the slopes are the filtered slopes.

    Returns:
        `max(slope_sq - slope·slope, 0)`.
    """
    var raw = sample.slope_sq - (
        sample.slope_x * sample.slope_x + sample.slope_z * sample.slope_z
    )
    if raw < 0.0:
        return 0.0
    return raw


def shader_time(clock: Duration) -> Duration:
    """Return the shader time Clearwater passes into the spectrum.

    The frame loop multiplies the clock by 0.9 before `runFFT`.

    Args:
        clock: Seconds since the start, the page's `t`.

    Returns:
        `0.9 * clock`.
    """
    return Duration(clock.value * 0.9, SECOND)
