# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The height and slope grid the water shader samples.

`resolve_surface` is the resolve shader: height, `∂h/∂x`, `∂h/∂z`, and the
squared slope that LEAN mapping turns into a variance. Sampling repeats
across the patch, bilinearly, the way the page's `texture` call does.
"""

from extensions.water.field import ComplexField, fft2
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

    def __init__(out self, patch: Length, var field: ComplexField):
        """Store a resolved grid.

        Args:
            patch: The world length of one tile.
            field: Height, slopes and squared slope, four channels.
        """
        self.patch = patch
        self.field = field^


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
