# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rolling ground, the masks of what grows on it, and its meshes.

`Ground` answers questions about a point: how high the ground is, how
thick and how tall the grass is, how dry it is, how many broad-leaf
plants grow there, and how many poppies bloom. Each answer is slow value
noise, so each is a patch meters wide.

**A canyon** can cross the ground toward -z. Its floor lies `depth`
below the near side, and its far plateau stands `rise` above it, so the
far wall shows above the near rim. `cliff_wall` builds that wall as a
face of rock.

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
from std.math import abs, cos, pi, pow, sin
from units.si import METER, Length

# The linear color of grass seen from far away.
comptime FAR_GRASS = Vector3(0.065, 0.115, 0.020)
# The linear color of short grass seen from far away: lighter and more
# yellow than the tall grass, which shades itself.
comptime FAR_LAWN = Vector3(0.090, 0.135, 0.030)
# The linear color of dry grass seen from far away.
comptime FAR_STRAW = Vector3(0.150, 0.130, 0.045)
# The linear color of a poppy patch seen from far away.
comptime FAR_POPPY = Vector3(0.200, 0.040, 0.012)
# The linear color of the ground where the grass is short or thin.
comptime SOIL = Vector3(0.070, 0.074, 0.030)
# The linear color of the mountains.
comptime STONE = Vector3(0.036, 0.044, 0.056)
# How wide the step at each rim of a canyon is, in meters.
comptime RIM = Float32(6)
# The linear colors of a cliff: its rock, its dark bands, and the moss
# along its top.
comptime ROCK = Vector3(0.095, 0.092, 0.088)
comptime ROCK_DARK = Vector3(0.036, 0.036, 0.038)
comptime MOSS = Vector3(0.070, 0.100, 0.030)
# The linear color of snow on the highest peaks, and the rows across the
# ring of mountains.
comptime SNOW = Vector3(0.30, 0.32, 0.36)
comptime RIDGE_ROWS = 9
# The radius, in lattice units, of the circle a ridge reads its noise on.
# About seven ridges a radian.
comptime RIDGE_LOBES = Float32(7)


def _ramp(start: Float32, end: Float32, x: Float32) -> Float32:
    """Return zero at `start`, one at `end`, and a smooth rise between.

    `start` can be greater than `end`, for a ramp that rises toward -z.
    """
    var t = min(Float32(1), max(Float32(0), (x - start) / (end - start)))
    return t * t * (3 - 2 * t)


@fieldwise_init
struct Canyon(ImplicitlyCopyable):
    """A canyon across the ground toward -z: a near rim, a far rim, a
    floor below the near side, and a far plateau above it."""

    # How far toward -z the near rim is, and the far rim.
    var near: Length
    var far: Length
    # How far the floor is below the near side.
    var depth: Length
    # How far the far plateau stands above the near side.
    var rise: Length

    def check(self) raises:
        """Refuse a canyon that cannot be cut.

        Raises:
            Error: If the near rim is not from 0 to 10 kilometers away,
                the far rim is not at least `RIM` beyond it and within 10
                kilometers, or the depth or the rise is not from 0 to 1
                kilometer.
        """
        require_between(
            self.near.to(METER),
            0,
            1.0e4,
            "A canyon's near rim must be from 0 to 10 kilometers away",
        )
        require_between(
            self.far.to(METER),
            self.near.to(METER) + 2 * RIM,
            1.0e4,
            "A canyon's far rim must be beyond its near rim",
        )
        require_between(
            self.depth.to(METER),
            0,
            1000,
            "A canyon must be from 0 to 1 kilometer deep",
        )
        require_between(
            self.rise.to(METER),
            0,
            1000,
            "A canyon's far side must rise from 0 to 1 kilometer",
        )

    def cut(self, z: Float32) -> Float32:
        """Return how far the canyon moves the ground at a z.

        Args:
            z: The point's z, in meters.

        Returns:
            Zero on the near side, minus `depth` on the floor, and `rise`
            on the far plateau, with a smooth step `RIM` wide at each rim.
        """
        var near = -self.near.to(METER)
        var far = -self.far.to(METER)
        var down = _ramp(near, near - RIM, z)
        var up = _ramp(far + RIM, far, z)
        return self.rise.to(METER) * up - self.depth.to(METER) * down * (1 - up)


def no_canyon() -> Canyon:
    """Return a canyon that cuts nothing.

    Returns:
        A canyon of no depth and no rise.
    """
    return Canyon(
        Length(1.0e3, METER),
        Length(2.0e3, METER),
        Length(0.0, METER),
        Length(0.0, METER),
    )


struct Ground(ImplicitlyCopyable):
    """Rolling hills, the patches of grass, straw and poppies, and a
    canyon."""

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
    # The canyon across the ground.
    var canyon: Canyon

    def __init__(
        out self,
        seed: Int = 3,
        hill_height: Length = Length(1.2, METER),
        hill_length: Length = Length(30.0, METER),
        climb: Float32 = 0.0,
        patch_length: Length = Length(6.0, METER),
        canyon: Canyon = no_canyon(),
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
            canyon: The canyon across the ground. `no_canyon` cuts
                nothing.

        Raises:
            Error: If `check` refuses a value.
        """
        self.seed = seed
        self.hill_height = hill_height
        self.hill_length = hill_length
        self.climb = climb
        self.patch_length = patch_length
        self.canyon = canyon
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
        self.canyon.check()

    def height_at(self, x: Float32, z: Float32) -> Float32:
        """Return the ground's height at a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The height, in meters, the canyon's cut included.
        """
        return self.hills_at(x, z) + self.canyon.cut(z)

    def hills_at(self, x: Float32, z: Float32) -> Float32:
        """Return the hills' height at a point, without the canyon.

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

    def tallness(self, x: Float32, z: Float32) -> Float32:
        """Return how tall the grass grows at a point, from zero to one.

        Zero is short grass, as on a path or where animals graze, and one
        is the meadow's full height. The edge between them is sharp, so
        tall grass stands in islands.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The tallness.
        """
        var length = self.patch_length.to(METER) * 1.6
        var raw = layered_noise(x / length, z / length, self.seed + 40)
        return _ramp(0.36, 0.44, raw)

    def weeds(self, x: Float32, z: Float32) -> Float32:
        """Return how many broad-leaf plants grow at a point, from zero to
        one.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The share of the most there can be.
        """
        var length = self.patch_length.to(METER) * 0.8
        var raw = value_noise(x / length, z / length, self.seed + 50)
        return 0.35 + 0.65 * _ramp(0.35, 0.65, raw)

    def far_color(self, x: Float32, z: Float32) -> Vector3:
        """Return the linear color of the ground and its grass from far.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            Soil where the grass is thin, the far grass where it is thick,
            tinted by the straw and the poppies.
        """
        var green = FAR_LAWN + (FAR_GRASS - FAR_LAWN) * self.tallness(x, z)
        green = green + (FAR_STRAW - green) * (self.dryness(x, z) * 0.5)
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
        An indexed geometry with `position` and `color`, `RIDGE_ROWS` rows
        deep from the foot over the crest to the far foot. Gullies cut the
        slopes, and snow lies on the highest. Compute its normals before
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
        var crag = value_noise(
            c * RIDGE_LOBES * 9 + 20, s * RIDGE_LOBES * 9, seed + 2
        )
        peak = 0.3 + 0.7 * pow(peak, Float32(1.2)) * (
            0.45 + 0.45 * detail + 0.1 * crag
        )
        for row in range(RIDGE_ROWS):  # pragma: no branch
            # Across the ring the range rises to its crest and falls
            # again, cut by gullies that run down from the crest.
            var f = Float32(row) / Float32(RIDGE_ROWS - 1)
            var radial = inner + (outer - inner) * f
            var gully = value_noise(
                c * RIDGE_LOBES * 6 + f * 5, s * RIDGE_LOBES * 6, seed + 3
            )
            # The sine of pi rounds to a little below zero, and a power of
            # a negative number is NaN.
            var arch = max(Float32(0), sin(f * Float32(pi)))
            var rise = pow(arch, Float32(0.8)) * (0.7 + 0.6 * gully)
            var y = top * peak * rise
            positions.append(c * radial)
            positions.append(y)
            positions.append(s * radial)
            var color = STONE + (SNOW - STONE) * _ramp(0.8 * top, 0.95 * top, y)
            colors.append(color.x)
            colors.append(color.y)
            colors.append(color.z)
    var index = List[Int]()
    for column in range(columns):  # pragma: no branch
        for row in range(RIDGE_ROWS - 1):  # pragma: no branch
            var a = column * RIDGE_ROWS + row
            var b = a + RIDGE_ROWS
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


def cliff_wall(
    ground: Ground, width: Length, columns: Int, rows: Int, seed: Int
) raises -> BufferGeometry:
    """Return the far wall of a ground's canyon: a cliff face toward +z.

    The face stands just in front of the far rim, so it hides the ground's
    own coarse step there. It runs from the canyon's floor to a little
    above the far plateau. It leans back as it rises, juts in ledges, and
    is banded by its strata. Moss grows along its top.

    Args:
        ground: The ground; its canyon and its hills are read.
        width: How wide the wall is, across x, centered on zero, from 1
            meter to 100 kilometers.
        columns: The cells across, from 2 to 4096.
        rows: The cells up, from 2 to 1024.
        seed: Which rock to grow.

    Returns:
        An indexed geometry with `position` and `color`. Compute its
        normals before it is lit.

    Raises:
        Error: If a value is out of range, or the canyon has no wall:
            neither depth nor rise.
    """
    require_between(
        width.to(METER),
        1,
        1.0e5,
        "A cliff must be from 1 meter to 100 kilometers wide",
    )
    require_count_between(
        columns, 2, 4096, "A cliff must have from 2 to 4096 columns"
    )
    require_count_between(
        rows, 2, 1024, "A cliff must have from 2 to 1024 rows"
    )
    ref canyon = ground.canyon
    var tall = canyon.depth.to(METER) + canyon.rise.to(METER)
    if tall <= 0:
        raise Error("A canyon of no depth and no rise has no wall")
    var face = -canyon.far.to(METER) + RIM + 1
    var half = width.to(METER) * 0.5
    var positions = List[Float32]()
    var colors = List[Float32]()
    var side = columns + 1
    positions.reserve(3 * side * (rows + 1))
    colors.reserve(3 * side * (rows + 1))
    for row in range(rows + 1):  # pragma: no branch
        var v = Float32(row) / Float32(rows)
        for col in range(side):  # pragma: no branch
            var x = -half + 2 * half * Float32(col) / Float32(columns)
            var bottom = ground.hills_at(x, face) - canyon.depth.to(METER)
            var crest = 1.5 * value_noise(x / 14, 3.5, seed + 3)
            var top = (
                ground.hills_at(x, face - RIM) + canyon.rise.to(METER) + crest
            )
            var y = bottom + (top + 0.6 - bottom) * v
            # Weathering cuts a cliff into vertical flutes and buttresses,
            # with a few ledges across them.
            var buttress = value_noise(x / 14, y / 45, seed)
            var flute = value_noise(x / 2.2, y / 18, seed + 1)
            var ledge = value_noise(x / 6, y / 2.5, seed + 4)
            var jut = tall * (
                (1 - v) * 0.12 + 0.09 * buttress + 0.022 * flute + 0.008 * ledge
            )
            positions.append(x)
            positions.append(y)
            positions.append(face + jut)
            var band = value_noise(x / 60, y / 3, seed + 2)
            var streak = value_noise(x / 2.4, y / 25, seed + 5)
            var c = ROCK + (ROCK_DARK - ROCK) * min(
                Float32(1), max(Float32(0), (band - 0.45) * 3)
            )
            c = c * (
                0.5 + 0.4 * v + 0.35 * (flute - 0.5) + 0.4 * (streak - 0.5)
            )
            c = c + (MOSS - c) * _ramp(Float32(0.9), Float32(1), v)
            colors.append(c.x)
            colors.append(c.y)
            colors.append(c.z)
    var index = List[Int]()
    index.reserve(6 * columns * rows)
    for row in range(rows):  # pragma: no branch
        for col in range(columns):  # pragma: no branch
            var a = row * side + col
            var b = a + side
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
