# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rolling ground, the masks of what grows on it, and its meshes.

`Ground` answers four questions about a point: how high the ground is,
how thick the grass is, how dry it is, and how many poppies bloom there.
Each answer is slow value noise, so each is a patch meters wide.

**The ground is the far grass.** The grass thins with distance, and past
its last level of detail it is not drawn at all. The ground mesh carries
the color of the grass seen from far away where the grass grows, and the
color of soil where it does not. The last blades then fade into a ground
of their own color, and the eye does not see where the field ends. The
same trick gives distant poppy patches a red tint.

`mesh` spaces its rows closer near the middle, where the camera stands,
and further apart toward the edge. `ridge_ring` is a ring of mountains
far away, for the fog to wash out.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.noise import layered_noise, value_noise
from math.vector3 import Vector3
from std.math import abs, cos, pi, sin
from units.si import METER, Length

# The linear color of grass seen from far away.
comptime FAR_GRASS = Vector3(0.050, 0.120, 0.016)
# The linear color of dry grass seen from far away.
comptime FAR_STRAW = Vector3(0.150, 0.130, 0.045)
# The linear color of a poppy patch seen from far away.
comptime FAR_POPPY = Vector3(0.200, 0.040, 0.012)
# The linear color of bare soil.
comptime SOIL = Vector3(0.060, 0.045, 0.028)
# The linear color of the mountains.
comptime STONE = Vector3(0.110, 0.115, 0.120)
# The radius, in lattice units, of the circle a ridge reads its noise on.
# About six ridges a radian.
comptime RIDGE_LOBES = Float32(6)


struct Ground(ImplicitlyCopyable):
    """Rolling hills, and the patches of grass, straw and poppies."""

    # Which noise fields to read.
    var seed: Int
    # How far the hills rise and fall from the mean.
    var hill_height: Length
    # How long one hill is.
    var hill_length: Length
    # How far the ground climbs per meter toward -z, to raise a ridge
    # behind the field. Zero is level on average.
    var climb: Float32
    # How long one patch of grass, straw or poppies is.
    var patch_length: Length

    def __init__(
        out self,
        seed: Int = 3,
        hill_height: Length = Length(1.2, METER),
        hill_length: Length = Length(30.0, METER),
        climb: Float32 = 0.0,
        patch_length: Length = Length(6.0, METER),
    ) raises:
        """Create ground and check it.

        Args:
            seed: Which noise fields to read.
            hill_height: How far the hills rise and fall, from 0 to 1
                kilometer.
            hill_length: How long one hill is, from 1 meter to 100
                kilometers.
            climb: How far the ground climbs per meter toward -z, from
                -1 to 1.
            patch_length: How long one patch is, from 10 centimeters to 1
                kilometer.

        Raises:
            Error: If `check` refuses a value.
        """
        self.seed = seed
        self.hill_height = hill_height
        self.hill_length = hill_length
        self.climb = climb
        self.patch_length = patch_length
        self.check()

    def check(self) raises:
        """Refuse a value outside the range `__init__` names.

        Raises:
            Error: If a value is out of its range, or NaN.
        """
        require_between(
            self.hill_height.to(METER),
            0,
            1000,
            "Hills must be from 0 to 1 kilometer high",
        )
        require_between(
            self.hill_length.to(METER),
            1,
            1.0e5,
            "A hill must be from 1 meter to 100 kilometers long",
        )
        require_between(self.climb, -1, 1, "The ground must climb from -1 to 1")
        require_between(
            self.patch_length.to(METER),
            0.1,
            1000,
            "A patch must be from 10 centimeters to 1 kilometer long",
        )

    def height_at(self, x: Float32, z: Float32) -> Float32:
        """Return the ground's height at a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The height, in meters.
        """
        var length = self.hill_length.to(METER)
        var hills = layered_noise(x / length, z / length, self.seed)
        return (hills - 0.5) * 2 * self.hill_height.to(METER) - self.climb * z

    def normal_at(self, x: Float32, z: Float32) -> Vector3:
        """Return the ground's unit normal at a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The normal, by central differences ten centimeters apart.
        """
        var e = Float32(0.1)
        var dx = self.height_at(x + e, z) - self.height_at(x - e, z)
        var dz = self.height_at(x, z + e) - self.height_at(x, z - e)
        var n = Vector3(-dx, 2 * e, -dz)
        return n / n.length()

    def cover(self, x: Float32, z: Float32) -> Float32:
        """Return how thick the grass is at a point, from zero to one.

        Zero is bare soil. Most of the field is near one, with bare and
        thin patches.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The cover.
        """
        var length = self.patch_length.to(METER)
        var raw = layered_noise(x / length, z / length, self.seed + 10)
        return min(Float32(1), max(Float32(0), (raw - 0.2) * 3.5))

    def dryness(self, x: Float32, z: Float32) -> Float32:
        """Return how dry the grass is at a point, from zero to one.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The dryness.
        """
        var length = self.patch_length.to(METER) * 1.7
        var raw = value_noise(x / length, z / length, self.seed + 20)
        return min(Float32(1), max(Float32(0), (raw - 0.45) * 2.5))

    def bloom(self, x: Float32, z: Float32) -> Float32:
        """Return how many poppies bloom at a point, from zero to one.

        Poppies grow in drifts: most of the field has none, and a drift
        has many.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The bloom.
        """
        var length = self.patch_length.to(METER) * 1.3
        var raw = layered_noise(x / length, z / length, self.seed + 30)
        return min(Float32(1), max(Float32(0), (raw - 0.64) * 6))

    def far_color(self, x: Float32, z: Float32) -> Vector3:
        """Return the linear color of the ground and its grass from far.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            Soil where the grass is thin, the far grass where it is thick,
            tinted by the straw and the poppies.
        """
        var green = FAR_GRASS + (FAR_STRAW - FAR_GRASS) * (
            self.dryness(x, z) * 0.5
        )
        green = green + (FAR_POPPY - green) * (self.bloom(x, z) * 0.35)
        return SOIL + (green - SOIL) * self.cover(x, z)

    def mesh(
        self, span: Length, cells: Int, center_x: Float32, center_z: Float32
    ) raises -> BufferGeometry:
        """Return a square of ground with its far colors.

        The rows are spaced as the square of their distance from the
        middle, so the cells are small near the middle and large at the
        edge.

        Args:
            span: The side of the square, from 1 meter to 100 kilometers.
            cells: The cells along a side, an even count from 2 to 1024.
            center_x: The middle's x, in meters.
            center_z: The middle's z, in meters.

        Returns:
            An indexed geometry with `position` and `color`. Compute its
            normals before it is lit.

        Raises:
            Error: If `span` or `cells` is out of range.
        """
        require_between(
            span.to(METER),
            1,
            1.0e5,
            "Ground must be from 1 meter to 100 kilometers across",
        )
        require_count_between(
            cells, 2, 1024, "Ground must be from 2 to 1024 cells across"
        )
        if cells % 2 != 0:
            raise Error("Ground must have an even count of cells across")
        var half = span.to(METER) * 0.5
        var positions = List[Float32]()
        var colors = List[Float32]()
        var side = cells + 1
        positions.reserve(3 * side * side)
        colors.reserve(3 * side * side)
        for row in range(side):  # pragma: no branch
            var v = Float32(row) / Float32(cells) * 2 - 1
            var z = center_z + half * v * abs(v)
            for col in range(side):  # pragma: no branch
                var u = Float32(col) / Float32(cells) * 2 - 1
                var x = center_x + half * u * abs(u)
                positions.append(x)
                positions.append(self.height_at(x, z))
                positions.append(z)
                var color = self.far_color(x, z)
                colors.append(color.x)
                colors.append(color.y)
                colors.append(color.z)
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
        geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
        geometry.set_index(_grid_index(cells))
        return geometry^


def _grid_index(cells: Int) -> List[Int]:
    """Return the triangles of a grid of `cells` by `cells`, wound to face
    +y."""
    var index = List[Int]()
    index.reserve(6 * cells * cells)
    var side = cells + 1
    for row in range(cells):  # pragma: no branch
        for col in range(cells):  # pragma: no branch
            var a = row * side + col
            var b = a + side
            index.append(a)
            index.append(b)
            index.append(a + 1)
            index.append(a + 1)
            index.append(b)
            index.append(b + 1)
    return index^


def ridge_ring(
    radius: Length, depth: Length, height: Length, columns: Int, seed: Int
) raises -> BufferGeometry:
    """Return a ring of mountains round the origin.

    Each column of the ring rises to a ridge. The ridge height is value
    noise round the ring, sharpened so the peaks are narrow.

    Args:
        radius: How far the ring's inner edge is, from 10 meters to 100
            kilometers.
        depth: How deep the ring is, from 1 meter to 100 kilometers.
        height: How high the tallest peak is, from 0 to 10 kilometers.
        columns: How many columns go round, from 8 to 4096.
        seed: Which ridge to grow.

    Returns:
        An indexed geometry with `position` and `color`, three rows deep:
        the foot, the ridge and the far foot. Compute its normals before
        it is lit.

    Raises:
        Error: If a value is out of range.
    """
    require_between(
        radius.to(METER),
        10,
        1.0e5,
        "A ridge must be from 10 meters to 100 kilometers away",
    )
    require_between(
        depth.to(METER),
        1,
        1.0e5,
        "A ridge must be from 1 meter to 100 kilometers deep",
    )
    require_between(
        height.to(METER),
        0,
        1.0e4,
        "A ridge must be from 0 to 10 kilometers high",
    )
    require_count_between(
        columns, 8, 4096, "A ridge must have from 8 to 4096 columns"
    )
    var inner = radius.to(METER)
    var outer = inner + depth.to(METER)
    var top = height.to(METER)
    var positions = List[Float32]()
    var colors = List[Float32]()
    for column in range(columns + 1):  # pragma: no branch
        var t = Float32(column) / Float32(columns)
        var angle = t * 2 * Float32(pi)
        var c = cos(angle)
        var s = sin(angle)
        # Read the noise round a circle, so the ring closes with no seam.
        var peak = value_noise(c * RIDGE_LOBES + 50, s * RIDGE_LOBES, seed)
        var detail = value_noise(
            c * RIDGE_LOBES * 3, s * RIDGE_LOBES * 3 + 50, seed + 1
        )
        peak = peak * peak * (0.4 + 0.6 * detail)
        var mid = (inner + outer) * 0.5
        var rows: List[Vector3] = [
            Vector3(c * inner, 0, s * inner),
            Vector3(c * mid, top * peak, s * mid),
            Vector3(c * outer, 0, s * outer),
        ]
        for row in range(3):  # pragma: no branch
            positions.append(rows[row].x)
            positions.append(rows[row].y)
            positions.append(rows[row].z)
            colors.append(STONE.x)
            colors.append(STONE.y)
            colors.append(STONE.z)
    var index = List[Int]()
    for column in range(columns):  # pragma: no branch
        for row in range(2):  # pragma: no branch
            var a = column * 3 + row
            var b = a + 3
            index.append(a)
            index.append(a + 1)
            index.append(b)
            index.append(a + 1)
            index.append(b + 1)
            index.append(b)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
    geometry.set_index(index^)
    return geometry^
