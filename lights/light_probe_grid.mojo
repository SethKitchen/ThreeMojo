# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box of light probes, from three.js
`examples/jsm/lighting/LightProbeGrid.js`.

One light probe lights every surface of a scene alike. A room with a
bright window and a dark corner needs more than one. A `LightProbeGrid`
holds a probe at each point of a regular grid in a box: nine spherical
harmonic colors each, bands zero to two. `renderers.light_probe_grid_utils`
bakes them by drawing the scene into a cube at each point. A surface
takes the probes of the cell it is in, blended by where it lies in the
cell, and catches their irradiance at its normal.

**The lookup.** three.js stores the coefficients in 3D textures one texel
for each probe and reads them with a linear filter, the box inset by half
a texel so the corner probes sit at the box's corners. That is a
trilinear blend of the eight probes around the surface, and the edge
probes past the box. `grid_taps` gives the eight probes and their
weights. Both backends call it, and both blend the coefficients and then
take the irradiance in one order, so their sums round alike.

**How it lights.** The blend adds to the ambient term and the light
probes, as a `LightProbe` adds: `Lighting.ambient_at`. A matte surface
scatters it through `BRDF_Lambert`, and a physical surface through its
diffuse term. `intensity` scales every coefficient.

This module lives in `lights/`, beside `light_probe.mojo`. three.js's
`lighting/` directory has no counterpart here, and a new top-level
package would change the build for every other package.
"""

from math.spherical_harmonics3 import SH_COUNT, SphericalHarmonics3
from math.vector3 import Vector3
from std.math import floor, isfinite, max, min


@fieldwise_init
struct GridTaps(ImplicitlyCopyable):
    """The eight probes a position blends, and their weights.

    Corner `c` is `x` one step on when bit zero of `c` is set, `y` when
    bit one is, and `z` when bit two is.
    """

    # Each corner's probe, its index in `LightProbeGrid.probes`.
    var probes: SIMD[DType.int32, 8]
    # Each corner's weight. They add to one.
    var weights: SIMD[DType.float32, 8]


@fieldwise_init
struct _AxisTap(ImplicitlyCopyable):
    """One axis of a lookup: the lower probe, the step to the upper one,
    and how far toward it."""

    var index: Int
    var step: Int
    var fraction: Float32


def _axis_tap(
    coordinate: Float32, low: Float32, high: Float32, count: Int
) -> _AxisTap:
    """Return one axis's lower probe, step and fraction, clamped to the
    box as a clamped texture read is."""
    var along = (coordinate - low) / (high - low)
    along = min(max(along, Float32(0)), Float32(1)) * Float32(count - 1)
    var index = Int(floor(along))
    if index >= count - 1:
        return _AxisTap(count - 1, 0, 0)
    return _AxisTap(index, 1, along - Float32(index))


def grid_taps(
    position: Vector3,
    low: Vector3,
    high: Vector3,
    count_x: Int,
    count_y: Int,
    count_z: Int,
) -> GridTaps:
    """Return the eight probes a position blends and their weights: a
    trilinear read of three.js's probe textures.

    Both backends call it.

    Args:
        position: Where the surface is, in world space.
        low: The box's lowest corner, where the first probe is.
        high: The box's highest corner, where the last probe is.
        count_x: How many probes along x. At least one.
        count_y: How many probes along y. At least one.
        count_z: How many probes along z. At least one.

    Returns:
        The probes and their weights. A position outside the box takes
        the probes on its nearest face.
    """
    var ax = _axis_tap(position.x, low.x, high.x, count_x)
    var ay = _axis_tap(position.y, low.y, high.y, count_y)
    var az = _axis_tap(position.z, low.z, high.z, count_z)
    var probes = SIMD[DType.int32, 8](0)
    var weights = SIMD[DType.float32, 8](0)
    for corner in range(8):  # pragma: no branch
        var ox = corner & 1
        var oy = (corner >> 1) & 1
        var oz = (corner >> 2) & 1
        var x = ax.index + ox * ax.step
        var y = ay.index + oy * ay.step
        var z = az.index + oz * az.step
        probes[corner] = Int32(x + count_x * (y + count_y * z))
        var wx = ax.fraction if ox == 1 else 1 - ax.fraction
        var wy = ay.fraction if oy == 1 else 1 - ay.fraction
        var wz = az.fraction if oz == 1 else 1 - az.fraction
        weights[corner] = wx * wy * wz
    return GridTaps(probes, weights)


struct LightProbeGrid(Copyable, Movable):
    """A box of light probes on a regular grid, three.js's
    `LightProbeGrid`.

    An empty grid, `LightProbeGrid()`, holds no probe and lights nothing.
    """

    # The box's lowest corner, where the first probe stands.
    var low: Vector3
    # The box's highest corner, where the last probe stands.
    var high: Vector3
    # How many probes along each axis.
    var count_x: Int
    var count_y: Int
    var count_z: Int
    # What every coefficient is multiplied by.
    var intensity: Float32
    # One probe per point, x fastest, then y, then z. Darkness until the
    # grid is baked.
    var probes: List[SphericalHarmonics3]

    def __init__(out self):
        """Create an empty grid, which lights nothing."""
        self.low = Vector3(0, 0, 0)
        self.high = Vector3(0, 0, 0)
        self.count_x = 0
        self.count_y = 0
        self.count_z = 0
        self.intensity = 1
        self.probes = List[SphericalHarmonics3]()

    def __init__(
        out self,
        low: Vector3,
        high: Vector3,
        count_x: Int,
        count_y: Int,
        count_z: Int,
        intensity: Float32 = 1.0,
    ) raises:
        """Create a grid of dark probes over a box.

        Args:
            low: The box's lowest corner.
            high: The box's highest corner.
            count_x: How many probes along x.
            count_y: How many probes along y.
            count_z: How many probes along z.
            intensity: What every coefficient is multiplied by.

        Raises:
            Error: If a count is below one; a corner is not finite; the
                box is not wider than zero on each axis; or the intensity
                is negative or not finite.
        """
        self.low = low
        self.high = high
        self.count_x = count_x
        self.count_y = count_y
        self.count_z = count_z
        self.intensity = intensity
        self.probes = List[SphericalHarmonics3]()
        self.validate()
        for _ in range(self.count()):  # pragma: no branch
            self.probes.append(SphericalHarmonics3())

    def __init__(out self, *, copy: Self):
        """Copy another grid, its probes included.

        Args:
            copy: The grid to copy.
        """
        self.low = copy.low
        self.high = copy.high
        self.count_x = copy.count_x
        self.count_y = copy.count_y
        self.count_z = copy.count_z
        self.intensity = copy.intensity
        self.probes = copy.probes.copy()

    def validate(self) raises:
        """Refuse a grid that cannot be looked up.

        Raises:
            Error: If a count is below one; a corner is not finite; the
                box is not wider than zero on each axis; the intensity is
                negative or not finite; or a probe's coefficients are not
                finite.
        """
        if self.count_x < 1 or self.count_y < 1 or self.count_z < 1:
            raise Error("A light probe grid needs one probe or more a side")
        if not _finite(self.low) or not _finite(self.high):
            raise Error("A light probe grid's corners must be finite")
        if (
            self.high.x <= self.low.x
            or self.high.y <= self.low.y
            or self.high.z <= self.low.z
        ):
            raise Error(
                "A light probe grid's box must be wider than zero on each axis"
            )
        if not isfinite(self.intensity) or self.intensity < 0:
            raise Error(
                "A light probe grid's intensity must be finite and not negative"
            )
        for index in range(len(self.probes)):
            if not self.probes[index].is_finite():
                raise Error("A light probe grid's coefficients must be finite")

    def count(self) -> Int:
        """Return how many probes the grid holds.

        Returns:
            The product of the three counts. Zero for an empty grid.
        """
        return self.count_x * self.count_y * self.count_z

    def is_empty(self) -> Bool:
        """Return True if the grid holds no probe.

        Returns:
            Whether it lights nothing.
        """
        return len(self.probes) == 0

    def index(self, x: Int, y: Int, z: Int) raises -> Int:
        """Return a probe's place in `probes`.

        Args:
            x: Its step along x.
            y: Its step along y.
            z: Its step along z.

        Returns:
            The place, x fastest.

        Raises:
            Error: If a step is outside the grid.
        """
        if (
            x < 0
            or y < 0
            or z < 0
            or x >= self.count_x
            or y >= self.count_y
            or z >= self.count_z
        ):
            raise Error("A light probe grid has no probe there")
        return x + self.count_x * (y + self.count_y * z)

    def position(self, index: Int) raises -> Vector3:
        """Return where a probe stands.

        The first and the last probe on an axis stand at the box's
        faces. A single probe on an axis stands in its middle.

        Args:
            index: The probe's place in `probes`.

        Returns:
            Its world position.

        Raises:
            Error: If the index is outside the grid.
        """
        if index < 0 or index >= self.count():
            raise Error("A light probe grid has no probe there")
        var x = index % self.count_x
        var y = (index // self.count_x) % self.count_y
        var z = index // (self.count_x * self.count_y)
        return Vector3(
            _along(self.low.x, self.high.x, x, self.count_x),
            _along(self.low.y, self.high.y, y, self.count_y),
            _along(self.low.z, self.high.z, z, self.count_z),
        )

    def taps(self, position: Vector3) -> GridTaps:
        """Return the eight probes a position blends and their weights.

        Args:
            position: Where the surface is, in world space.

        Returns:
            What `grid_taps` gives for this grid.
        """
        return grid_taps(
            position,
            self.low,
            self.high,
            self.count_x,
            self.count_y,
            self.count_z,
        )

    def sh_at(self, position: Vector3) -> SphericalHarmonics3:
        """Return the probes' blend at a position, before `intensity`.

        Each lane is summed over the eight corners in their order, as
        the kernel sums it.

        Args:
            position: Where the surface is, in world space.

        Returns:
            The coefficients. Darkness for an empty grid.
        """
        var blend = SphericalHarmonics3()
        if self.is_empty():
            return blend
        var taps = self.taps(position)
        for lane in range(SH_COUNT * 3):  # pragma: no branch
            var total = Float32(0)
            for corner in range(8):  # pragma: no branch
                total = (
                    total
                    + self.probes[Int(taps.probes[corner])].lanes[lane]
                    * taps.weights[corner]
                )
            blend.lanes[lane] = total
        return blend

    def irradiance_at(self, position: Vector3, normal: Vector3) -> Vector3:
        """Return the irradiance the grid gives a surface, times
        `intensity`: what `Lighting.ambient_at` adds.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, in world space.

        Returns:
            The irradiance, red, green and blue, before the division by
            pi.
        """
        var blend = self.sh_at(position)
        blend.scale(self.intensity)
        return blend.get_irradiance_at(normal)

    def scaled(self) -> LightProbeGrid:
        """Return a copy with `intensity` multiplied into every probe and
        an intensity of one, as `Lighting` holds it and the kernel reads
        it.

        Returns:
            The copy.
        """
        var out = LightProbeGrid(copy=self)
        for index in range(len(out.probes)):
            out.probes[index].scale(self.intensity)
        out.intensity = 1
        return out^

    def flatten(self) -> List[Float32]:
        """Return the grid as the kernel reads it: the low corner, the
        high corner, the three counts, and then the 27 lanes of each
        probe in order.

        Returns:
            `9 + 27 * count` floats, or none for an empty grid.
        """
        var flat = List[Float32]()
        if self.is_empty():
            return flat^
        flat.append(self.low.x)
        flat.append(self.low.y)
        flat.append(self.low.z)
        flat.append(self.high.x)
        flat.append(self.high.y)
        flat.append(self.high.z)
        flat.append(Float32(self.count_x))
        flat.append(Float32(self.count_y))
        flat.append(Float32(self.count_z))
        for index in range(len(self.probes)):
            for lane in range(SH_COUNT * 3):  # pragma: no branch
                flat.append(self.probes[index].lanes[lane])
        return flat^


# How many floats come before the probes in `LightProbeGrid.flatten`.
comptime GRID_HEADER = 9


def _along(low: Float32, high: Float32, step: Int, count: Int) -> Float32:
    """Return where probe `step` of `count` stands between two faces."""
    if count == 1:
        return (low + high) * 0.5
    return low + (high - low) * Float32(step) / Float32(count - 1)


def _finite(point: Vector3) -> Bool:
    """Return True if every component of a point is finite."""
    return isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
