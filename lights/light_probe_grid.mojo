# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box of light probes, from three.js
`examples/jsm/lighting/LightProbeGrid.js` and
`examples/jsm/tsl/lighting/LightProbeGridNode.js`.

A `LightProbeGrid` is a box `width` by `height` by `depth` around its
`position`, with a light probe at each point of a regular grid in it:
nine spherical harmonic colors each, bands zero to two.
`renderers.light_probe_grid_utils` bakes them. A surface takes the
probes around it and adds their irradiance at its normal to its indirect
light.

**The lookup.** `LightProbeGridNode` moves the surface half a probe
spacing along its normal, so a surface does not read the probe behind
it. It clamps the result to the box and reads the probes' 3D textures
there with a linear filter, the box inset by half a texel so the corner
probes sit at the box's corners. That is a trilinear blend of the eight
probes around the point. `grid_taps` gives the eight probes and their
weights. Both backends call it, and both blend the coefficients and then
take the irradiance in one order, so their sums round alike. The
irradiance is held at zero or above, times `intensity`.

**The falloff.** With a `falloff` above zero, a surface outside the box
takes less of the grid, `1 - smoothstep( 0, falloff, distance )` of the
distance from the box, so grids can blend. `grid_falloff` is that weight.

This module lives in `lights/`, beside `light_probe.mojo`. three.js's
`lighting/` directory has no counterpart here, and a new top-level
package would change the build for every other package.
"""

from math.smoothstep import smoothstep
from math.spherical_harmonics3 import SH_COUNT, SphericalHarmonics3
from math.vector3 import Vector3
from std.math import floor, isfinite, max, min, sqrt
from units.si import Length, METER

# Where a grid's size says to take its probe count from: three.js's
# `widthProbes` and the other two left out.
comptime AUTO_PROBES = 0


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
    coordinate: Float32, normal: Float32, low: Float32, high: Float32, count: Int
) -> _AxisTap:
    """Return one axis's lower probe, step and fraction: the position
    moved half a spacing along the normal, clamped to the box as a clamped
    texture read is."""
    if count == 1:
        return _AxisTap(0, 0, 0)
    var spacing = (high - low) / Float32(count - 1)
    var moved = coordinate + normal * spacing * 0.5
    var along = (moved - low) / (high - low)
    along = min(max(along, Float32(0)), Float32(1)) * Float32(count - 1)
    var index = Int(floor(along))
    if index >= count - 1:
        return _AxisTap(count - 1, 0, 0)
    return _AxisTap(index, 1, along - Float32(index))


def grid_taps(
    position: Vector3,
    normal: Vector3,
    low: Vector3,
    high: Vector3,
    count_x: Int,
    count_y: Int,
    count_z: Int,
) -> GridTaps:
    """Return the eight probes a surface blends and their weights, three.js's
    `LightProbeGridNode` texture read.

    Both backends call it.

    Args:
        position: Where the surface is, in world space.
        normal: Its unit normal, in world space.
        low: The box's lowest corner, where the first probe is.
        high: The box's highest corner, where the last probe is.
        count_x: How many probes along x. At least one.
        count_y: How many probes along y. At least one.
        count_z: How many probes along z. At least one.

    Returns:
        The probes and their weights. A point outside the box takes the
        probes on its nearest face.
    """
    var ax = _axis_tap(position.x, normal.x, low.x, high.x, count_x)
    var ay = _axis_tap(position.y, normal.y, low.y, high.y, count_y)
    var az = _axis_tap(position.z, normal.z, low.z, high.z, count_z)
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


def grid_falloff(
    position: Vector3, low: Vector3, high: Vector3, falloff: Float32
) -> Float32:
    """Return how much of a grid a surface takes, three.js's `falloff`
    weight: one inside the box, and `1 - smoothstep( 0, falloff, d )` at
    a distance `d` outside it.

    Both backends call it.

    Args:
        position: Where the surface is, in world space.
        low: The box's lowest corner.
        high: The box's highest corner.
        falloff: How far outside the box the grid fades out, in meters.
            Zero applies the grid everywhere.

    Returns:
        The weight, from zero to one.
    """
    if falloff <= 0:
        return 1
    var dx = max(low.x - position.x, Float32(0)) + max(
        position.x - high.x, Float32(0)
    )
    var dy = max(low.y - position.y, Float32(0)) + max(
        position.y - high.y, Float32(0)
    )
    var dz = max(low.z - position.z, Float32(0)) + max(
        position.z - high.z, Float32(0)
    )
    return 1 - smoothstep(0, falloff, sqrt(dx * dx + dy * dy + dz * dz))


def _default_probes(size: Length) -> Int:
    """Return three.js's default probe count for one side: one probe a
    meter and one more, at least two."""
    return max(2, Int(floor(size.to(METER) + 0.5)) + 1)


struct LightProbeGrid(Copyable, Movable):
    """A box of light probes on a regular grid, three.js's
    `LightProbeGrid`.

    An empty grid, `LightProbeGrid.none()`, holds no probe and lights
    nothing.
    """

    # The box's size, three.js's `width`, `height` and `depth`.
    var width: Length
    var height: Length
    var depth: Length
    # How many probes along each axis, three.js's `resolution`.
    var resolution_x: Int
    var resolution_y: Int
    var resolution_z: Int
    # The box's middle, three.js's `position`.
    var position: Vector3
    # What the irradiance is multiplied by, three.js's `intensity`.
    var intensity: Float32
    # How far outside the box the grid fades out, three.js's `falloff`.
    # Zero, the default, applies the grid everywhere.
    var falloff: Length
    # One probe per point, x fastest, then y, then z, three.js's texture
    # order. Darkness until the grid is baked.
    var probes: List[SphericalHarmonics3]

    def __init__(
        out self,
        width: Length = Length(1.0, METER),
        height: Length = Length(1.0, METER),
        depth: Length = Length(1.0, METER),
        width_probes: Int = AUTO_PROBES,
        height_probes: Int = AUTO_PROBES,
        depth_probes: Int = AUTO_PROBES,
        position: Vector3 = Vector3(0, 0, 0),
    ) raises:
        """Create a grid of dark probes, three.js's `new LightProbeGrid(
        width, height, depth, widthProbes, heightProbes, depthProbes )`.

        Args:
            width: The box's size along x.
            height: The box's size along y.
            depth: The box's size along z.
            width_probes: How many probes along x, or `AUTO_PROBES` for
                three.js's default, `max( 2, round( width ) + 1 )`.
            height_probes: How many probes along y, or `AUTO_PROBES`.
            depth_probes: How many probes along z, or `AUTO_PROBES`.
            position: The box's middle.

        Raises:
            Error: If `validate` refuses the grid.
        """
        self.width = width
        self.height = height
        self.depth = depth
        self.resolution_x = width_probes
        self.resolution_y = height_probes
        self.resolution_z = depth_probes
        if width_probes == AUTO_PROBES:
            self.resolution_x = _default_probes(width)
        if height_probes == AUTO_PROBES:
            self.resolution_y = _default_probes(height)
        if depth_probes == AUTO_PROBES:
            self.resolution_z = _default_probes(depth)
        self.position = position
        self.intensity = 1
        self.falloff = Length(0.0, METER)
        self.probes = List[SphericalHarmonics3]()
        self.validate()
        for _ in range(self.count()):  # pragma: no branch
            self.probes.append(SphericalHarmonics3())

    @staticmethod
    def none() -> LightProbeGrid:
        """Return an empty grid, which lights nothing: three.js's grid with
        no baked `texture`.

        Returns:
            The grid.
        """
        return LightProbeGrid(empty=True)

    def __init__(out self, *, copy: Self):
        """Copy another grid, its probes included.

        Args:
            copy: The grid to copy.
        """
        self.width = copy.width
        self.height = copy.height
        self.depth = copy.depth
        self.resolution_x = copy.resolution_x
        self.resolution_y = copy.resolution_y
        self.resolution_z = copy.resolution_z
        self.position = copy.position
        self.intensity = copy.intensity
        self.falloff = copy.falloff
        self.probes = copy.probes.copy()

    def __init__(out self, *, empty: Bool):
        """Create a grid with no probe.

        Args:
            empty: Ignored; it names this form.
        """
        self.width = Length(1.0, METER)
        self.height = Length(1.0, METER)
        self.depth = Length(1.0, METER)
        self.resolution_x = 0
        self.resolution_y = 0
        self.resolution_z = 0
        self.position = Vector3(0, 0, 0)
        self.intensity = 1
        self.falloff = Length(0.0, METER)
        self.probes = List[SphericalHarmonics3]()

    def validate(self) raises:
        """Refuse a grid that cannot be looked up.

        Raises:
            Error: If a probe count is below one; a size is not a positive
                finite length; the position is not finite; the intensity
                is negative or not finite; the falloff is negative or not
                finite; or a probe's coefficients are not finite.
        """
        if self.resolution_x < 1 or self.resolution_y < 1 or (
            self.resolution_z < 1
        ):
            raise Error("A light probe grid needs one probe or more a side")
        var width = self.width.to(METER)
        var height = self.height.to(METER)
        var depth = self.depth.to(METER)
        if not (
            isfinite(width)
            and isfinite(height)
            and isfinite(depth)
            and width > 0
            and height > 0
            and depth > 0
        ):
            raise Error("A light probe grid's size must be positive lengths")
        if not (
            isfinite(self.position.x)
            and isfinite(self.position.y)
            and isfinite(self.position.z)
        ):
            raise Error("A light probe grid's position must be finite")
        if not isfinite(self.intensity) or self.intensity < 0:
            raise Error(
                "A light probe grid's intensity must be finite and not negative"
            )
        var falloff = self.falloff.to(METER)
        if not isfinite(falloff) or falloff < 0:
            raise Error(
                "A light probe grid's falloff must be finite and not negative"
            )
        for index in range(len(self.probes)):
            if not self.probes[index].is_finite():
                raise Error("A light probe grid's coefficients must be finite")

    def count(self) -> Int:
        """Return how many probes the grid holds.

        Returns:
            The product of the three counts. Zero for an empty grid.
        """
        return self.resolution_x * self.resolution_y * self.resolution_z

    def is_empty(self) -> Bool:
        """Return True if the grid holds no probe.

        Returns:
            Whether it lights nothing.
        """
        return len(self.probes) == 0

    def low(self) -> Vector3:
        """Return the box's lowest corner, three.js's `boundingBox.min`.

        Returns:
            `position` less half the size.
        """
        return Vector3(
            self.position.x - self.width.to(METER) / 2,
            self.position.y - self.height.to(METER) / 2,
            self.position.z - self.depth.to(METER) / 2,
        )

    def high(self) -> Vector3:
        """Return the box's highest corner, three.js's `boundingBox.max`.

        Returns:
            `position` plus half the size.
        """
        return Vector3(
            self.position.x + self.width.to(METER) / 2,
            self.position.y + self.height.to(METER) / 2,
            self.position.z + self.depth.to(METER) / 2,
        )

    def index(self, x: Int, y: Int, z: Int) raises -> Int:
        """Return a probe's place in `probes`: three.js's texture order.

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
            or x >= self.resolution_x
            or y >= self.resolution_y
            or z >= self.resolution_z
        ):
            raise Error("A light probe grid has no probe there")
        return x + self.resolution_x * (y + self.resolution_y * z)

    def get_probe_position(self, x: Int, y: Int, z: Int) raises -> Vector3:
        """Return where a probe stands, three.js's `getProbePosition`.

        The first and the last probe on an axis stand at the box's
        faces. A single probe on an axis stands at `position`.

        Args:
            x: Its step along x.
            y: Its step along y.
            z: Its step along z.

        Returns:
            Its world position.

        Raises:
            Error: If a step is outside the grid.
        """
        _ = self.index(x, y, z)
        return Vector3(
            _along(
                self.position.x, self.width.to(METER), x, self.resolution_x
            ),
            _along(
                self.position.y, self.height.to(METER), y, self.resolution_y
            ),
            _along(
                self.position.z, self.depth.to(METER), z, self.resolution_z
            ),
        )

    def position_of(self, index: Int) raises -> Vector3:
        """Return where the probe at a place in `probes` stands.

        Args:
            index: The probe's place.

        Returns:
            Its world position.

        Raises:
            Error: If the index is outside the grid.
        """
        if index < 0 or index >= self.count():
            raise Error("A light probe grid has no probe there")
        var x = index % self.resolution_x
        var y = (index // self.resolution_x) % self.resolution_y
        var z = index // (self.resolution_x * self.resolution_y)
        return self.get_probe_position(x, y, z)

    def taps(self, position: Vector3, normal: Vector3) -> GridTaps:
        """Return the eight probes a surface blends and their weights.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, in world space.

        Returns:
            What `grid_taps` gives for this grid.
        """
        return grid_taps(
            position,
            normal,
            self.low(),
            self.high(),
            self.resolution_x,
            self.resolution_y,
            self.resolution_z,
        )

    def sh_at(self, position: Vector3, normal: Vector3) -> SphericalHarmonics3:
        """Return the probes' blend at a surface, before `intensity`.

        Each lane is summed over the eight corners in their order, as
        the kernel sums it.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, in world space.

        Returns:
            The coefficients. Darkness for an empty grid.
        """
        var blend = SphericalHarmonics3()
        if self.is_empty():
            return blend
        var taps = self.taps(position, normal)
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
        """Return the irradiance the grid gives a surface: three.js's
        `LightProbeGridNode`, what `Lighting.ambient_at` adds.

        The blend's irradiance at the normal, held at zero or above,
        times `intensity`, times `grid_falloff`.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, in world space.

        Returns:
            The irradiance, red, green and blue, before the division by
            pi. Zero for an empty grid.
        """
        var blend = self.sh_at(position, normal)
        blend.scale(self.intensity)
        var lift = blend.get_irradiance_at(normal)
        var weight = grid_falloff(
            position, self.low(), self.high(), self.falloff.to(METER)
        )
        return Vector3(
            max(lift.x, Float32(0)) * weight,
            max(lift.y, Float32(0)) * weight,
            max(lift.z, Float32(0)) * weight,
        )

    def scaled(self) -> LightProbeGrid:
        """Return a copy with `intensity` multiplied into every probe and
        an intensity of one, as `Lighting` holds it and the kernel reads
        it.

        The intensity is not negative, so it can be multiplied in before
        the irradiance is held at zero, where three.js multiplies after.

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
        high corner, the three counts, the falloff in meters, and then
        the 27 lanes of each probe in order.

        Returns:
            `GRID_HEADER + 27 * count` floats, or none for an empty grid.
        """
        var flat = List[Float32]()
        if self.is_empty():
            return flat^
        var low = self.low()
        var high = self.high()
        flat.append(low.x)
        flat.append(low.y)
        flat.append(low.z)
        flat.append(high.x)
        flat.append(high.y)
        flat.append(high.z)
        flat.append(Float32(self.resolution_x))
        flat.append(Float32(self.resolution_y))
        flat.append(Float32(self.resolution_z))
        flat.append(self.falloff.to(METER))
        # Not empty, as checked above.
        for index in range(len(self.probes)):  # pragma: no branch
            for lane in range(SH_COUNT * 3):  # pragma: no branch
                flat.append(self.probes[index].lanes[lane])
        return flat^


# How many floats come before the probes in `LightProbeGrid.flatten`.
comptime GRID_HEADER = 10


def _along(middle: Float32, size: Float32, step: Int, count: Int) -> Float32:
    """Return where probe `step` of `count` stands along a side of `size`
    around `middle`, three.js's `getProbePosition` for one axis."""
    if count == 1:
        return middle
    return middle - size / 2 + Float32(step) * size / Float32(count - 1)
