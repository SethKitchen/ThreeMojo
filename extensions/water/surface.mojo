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

The samplers read texels through `SurfaceTexels`, so the same arithmetic
runs on a `SurfaceField` and on a packed copy in device memory.
"""

from extensions.water.field import ComplexField, fft2
from extensions.water.filter import (
    anisotropic_step,
    lod_blend,
    major_axis_offset,
)
from extensions.water.resolution import SpectrumResolution
from extensions.water.spectrum import (
    build_spectrum,
    clearwater_patch,
    clearwater_slope,
    evolve_spectrum,
)
from math.norm import squared_length2
from std.math import floor, isfinite
from units.si import SECOND, Duration, Length


@fieldwise_init
struct SurfaceSample(ImplicitlyCopyable):
    """One filtered sample of the ocean surface."""

    var height: Float32
    var slope_x: Float32
    var slope_z: Float32
    var slope_sq: Float32

    def __add__(self, other: Self) -> Self:
        """Return the sum of two samples.

        Error: Never.

        Args:
            other: The sample to add.

        Returns:
            Each field added.

        """
        return SurfaceSample(
            self.height + other.height,
            self.slope_x + other.slope_x,
            self.slope_z + other.slope_z,
            self.slope_sq + other.slope_sq,
        )

    def __mul__(self, weight: Float32) -> Self:
        """Return this sample scaled by a weight.

        Error: Never.

        Args:
            weight: The scale.

        Returns:
            Each field scaled.

        """
        return SurfaceSample(
            self.height * weight,
            self.slope_x * weight,
            self.slope_z * weight,
            self.slope_sq * weight,
        )


trait SurfaceTexels:
    """Read access to a resolved surface and its mipmaps.

    Level 0 is the base grid. Level `k` is the `k`th coarser mip.
    """

    def surface_patch(self) -> Float32:
        """Return the world length of one tile, in meters.

        Returns:
            The patch length.
        """
        ...

    def surface_levels(self) -> Int:
        """Return how many mip levels follow the base grid.

        Returns:
            The count of coarser levels.
        """
        ...

    def surface_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base grid.

        Returns:
            The side length.
        """
        ...

    def surface_texel(self, level: Int, x: Int, y: Int) -> SurfaceSample:
        """Return one texel of a level.

        Args:
            level: The level. Zero or less is the base grid.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            Height, slopes and squared slope.
        """
        ...


struct SurfaceField(Copyable, Movable, SurfaceTexels):
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

    def surface_patch(self) -> Float32:
        """Return the world length of one tile, in meters.

        Returns:
            The patch length.
        """
        return self.patch.value

    def surface_levels(self) -> Int:
        """Return how many mip levels follow the base grid.

        Returns:
            The count of coarser levels.
        """
        return len(self.mips)

    def surface_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base grid.

        Returns:
            The side length.
        """
        if level <= 0:
            return self.field.n
        return self.mips[level - 1].n

    def surface_texel(self, level: Int, x: Int, y: Int) -> SurfaceSample:
        """Return one texel of a level.

        Args:
            level: The level. Zero or less is the base grid.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            Height, slopes and squared slope.
        """
        if level <= 0:
            return _texel(self.field, x, y)
        return _texel(self.mips[level - 1], x, y)


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
            out.put(x, y, 3, squared_length2[DType.float32](sx, sz))
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


def _index_fits(px: Float32) -> Bool:
    """Return True when `px` is a finite texel index.

    Args:
        px: A texel coordinate, in texels.

    Returns:
        True when `Int` of its floor is that coordinate.
    """
    var wide = Float64(px)
    return (
        isfinite(wide) and wide < Float64(Int.MAX) and wide > -Float64(Int.MAX)
    )


def _local_meters(coord: Float32, patch: Float32) -> Tuple[Bool, Float32]:
    """Return one coordinate folded into the first patch.

    Args:
        coord: A world position, in meters.
        patch: The patch length, in meters.

    Returns:
        Whether the position is finite, and its place in the first patch.
    """
    var turns = Float64(coord) / Float64(patch)
    if not isfinite(turns):
        return (False, Float32(0))
    var frac = turns - floor(turns)
    return (True, Float32(frac * Float64(patch)))


def _local_turn(turns: Float32) -> Tuple[Bool, Float32]:
    """Return a repeating texture coordinate folded into zero to one.

    Args:
        turns: How many patches across the position is.

    Returns:
        Whether the coordinate is finite, and its fraction.
    """
    var wide = Float64(turns)
    if not isfinite(wide):
        return (False, Float32(0))
    return (True, Float32(wide - floor(wide)))


def _wrap(index: Int, n: Int) -> Int:
    # Mojo's remainder is non-negative, so a negative index already wraps.
    return index % n


def sample_surface[
    S: SurfaceTexels
](surface: S, x: Float32, z: Float32) -> SurfaceSample:
    """Sample the surface at one world position, repeating the patch.

    Parameters:
        S: The surface storage.

    Args:
        surface: A resolved ocean.
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        The bilinear height and slopes. Variance for LEAN mapping is
        `slope_sq` minus the squared filtered slope, and it is not negative.
        A position that does not fit in an integer repeats. A position
        that is not finite is flat.
    """
    var n = surface.surface_side(0)
    var patch = surface.surface_patch()
    var sx = x
    var sz = z
    var px = sx / patch * Float32(n) - 0.5
    var pz = sz / patch * Float32(n) - 0.5
    if not _index_fits(px) or not _index_fits(pz):
        var ok_x: Bool
        var ok_z: Bool
        ok_x, sx = _local_meters(x, patch)
        ok_z, sz = _local_meters(z, patch)
        if not ok_x or not ok_z:
            return SurfaceSample(0, 0, 0, 0)
        px = sx / patch * Float32(n) - 0.5
        pz = sz / patch * Float32(n) - 0.5
    var x0 = Int(floor(px))
    var z0 = Int(floor(pz))
    var fx = px - Float32(x0)
    var fz = pz - Float32(z0)
    var x1 = _wrap(x0 + 1, n)
    var z1 = _wrap(z0 + 1, n)
    x0 = _wrap(x0, n)
    z0 = _wrap(z0, n)
    var s00 = surface.surface_texel(0, x0, z0)
    var s10 = surface.surface_texel(0, x1, z0)
    var s01 = surface.surface_texel(0, x0, z1)
    var s11 = surface.surface_texel(0, x1, z1)
    var a = s00 * (1.0 - fx) + s10 * fx
    var b = s01 * (1.0 - fx) + s11 * fx
    return a * (1.0 - fz) + b * fz


def sample_surface_smooth[
    S: SurfaceTexels
](surface: S, x: Float32, z: Float32) -> SurfaceSample:
    """Sample the surface with the page's cubic B-spline filter.

    Four bilinear taps. The page uses this on the two large tiles so a
    slope, and the sun glint on it, stays smooth.

    Parameters:
        S: The surface storage.

    Args:
        surface: A resolved ocean.
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        The cubic height and slopes.
    """
    var n = Float32(surface.surface_side(0))
    var patch = surface.surface_patch()
    var sx = x
    var sz = z
    var px = sx / patch * n - 0.5
    var pz = sz / patch * n - 0.5
    if not _index_fits(px) or not _index_fits(pz):
        var ok_x: Bool
        var ok_z: Bool
        ok_x, sx = _local_meters(x, patch)
        ok_z, sz = _local_meters(z, patch)
        if not ok_x or not ok_z:
            return SurfaceSample(0, 0, 0, 0)
        px = sx / patch * n - 0.5
        pz = sz / patch * n - 0.5
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
    var top = s00 * gx0 + s10 * gx1
    var bottom = s01 * gx0 + s11 * gx1
    return top * gz0 + bottom * gz1


def _texel(field: ComplexField, x: Int, y: Int) -> SurfaceSample:
    return SurfaceSample(
        field.channel(x, y, 0),
        field.channel(x, y, 1),
        field.channel(x, y, 2),
        field.channel(x, y, 3),
    )


def sample_surface_filtered[
    S: SurfaceTexels
](
    surface: S,
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

    Parameters:
        S: The surface storage.

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
        Float32(surface.surface_side(0)),
        Float32(surface.surface_side(0)),
        8.0,
        0.0,
        Float32(surface.surface_levels()),
    )
    var smooth = cubic
    if step.lod > 0.0:
        smooth = False
    if step.taps > 1:
        smooth = False
    if smooth:
        return sample_surface_smooth(surface, x, z)
    var u = x / surface.surface_patch()
    var v = z / surface.surface_patch()
    var acc = SurfaceSample(0.0, 0.0, 0.0, 0.0)
    var count = step.taps
    for i in range(count):  # pragma: no branch
        var o = major_axis_offset(i, count)
        var sample = _trilinear_uv(
            surface, u + step.du * o, v + step.dv * o, step.lod
        )
        acc = acc + sample
    return acc * (1.0 / Float32(count))


def _trilinear_uv[
    S: SurfaceTexels
](surface: S, u: Float32, v: Float32, lod: Float32) -> SurfaceSample:
    var levels = surface.surface_levels()
    var i0, i1, frac = lod_blend(lod, levels)
    var a = _sample_level(surface, i0, u, v)
    var b = _sample_level(surface, i1, u, v)
    return a * (1.0 - frac) + b * frac


def _sample_level[
    S: SurfaceTexels
](surface: S, level: Int, u: Float32, v: Float32) -> SurfaceSample:
    var n = surface.surface_side(level)
    var su = u
    var sv = v
    var px = su * Float32(n) - 0.5
    var pz = sv * Float32(n) - 0.5
    if not _index_fits(px) or not _index_fits(pz):
        var ok_u: Bool
        var ok_v: Bool
        ok_u, su = _local_turn(u)
        ok_v, sv = _local_turn(v)
        if not ok_u or not ok_v:
            return SurfaceSample(0, 0, 0, 0)
        px = su * Float32(n) - 0.5
        pz = sv * Float32(n) - 0.5
    var x0 = Int(floor(px))
    var z0 = Int(floor(pz))
    var fx = px - Float32(x0)
    var fz = pz - Float32(z0)
    var x1 = _wrap(x0 + 1, n)
    var z1 = _wrap(z0 + 1, n)
    x0 = _wrap(x0, n)
    z0 = _wrap(z0, n)
    var s00 = surface.surface_texel(level, x0, z0)
    var s10 = surface.surface_texel(level, x1, z0)
    var s01 = surface.surface_texel(level, x0, z1)
    var s11 = surface.surface_texel(level, x1, z1)
    var a = s00 * (1.0 - fx) + s10 * fx
    var b = s01 * (1.0 - fx) + s11 * fx
    return a * (1.0 - fz) + b * fz


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
