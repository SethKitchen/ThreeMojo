# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rolling ground, the masks of what grows on it, and its meshes.

`Ground` answers questions about a point: how high the ground is, how
bare it is, how thick and how tall the grass is, how dry it is, how many
broad-leaf plants grow there, and how many poppies bloom. Each answer is
slow value noise, so each is a patch meters wide.

**A pond** is a round basin. Its water lies at `Ground.water_level`, a
little below the hills at its middle. Ground outside the basin that would
lie lower is raised just above the water, so the water shows only in the
basin. Its shore is bare mud, and the grass round it is short.

**A lot** is a building's footprint. Nothing grows on it or on a bare
apron round it: see `lot_openness` and `lot_shade`.

**Bare ground** is dirt with no grass. `bare` is one in patches of dirt,
`dirt` of the field or so, and on a trail `trail_width` wide that winds
away from the camera's side of the field. The grass thins toward a bare
patch and is shorter at its edge. A `Clearing` is the shade round a
tree's foot. `openness` is zero at the foot and rises to one at the
shade's edge, and `litter_shade` browns the ground under it.

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
from extensions.vegetation.noise import hash01, layered_noise, value_noise
from math.vector3 import Vector3
from std.math import abs, cos, floor, pi, pow, sin, sqrt
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
# The linear colors of bare dirt, light and dark, and of the leaf litter
# in a tree's shade.
comptime DIRT = Vector3(0.260, 0.190, 0.115)
comptime DIRT_DARK = Vector3(0.140, 0.100, 0.060)
comptime LITTER = Vector3(0.070, 0.050, 0.026)
# The trail's course: its x where it passes z = `TRAIL_Z`, how far it
# drifts toward +x for each meter toward -z, and how far and how long it
# wanders from side to side, in meters.
comptime TRAIL_X = Float32(-7)
comptime TRAIL_Z = Float32(30)
comptime TRAIL_DRIFT = Float32(0.42)
comptime TRAIL_WANDER = Float32(3.5)
comptime TRAIL_BEND = Float32(13)
# How bare the middle of the trail is, so a few tufts grow on it, and how
# wide its edge is, where the grass thins out, in meters.
comptime TRAIL_WORN = Float32(0.92)
comptime TRAIL_EDGE = Float32(1.3)
# The share of a clearing's radius, out from the foot, that is bare.
comptime CLEARING_BARE = Float32(0.25)
# The share of a pond's radius that is its flat floor; how far its water
# lies below the lowest hills; and how far above the water its shore is
# bare mud, in meters.
comptime POND_FLAT = Float32(0.3)
comptime POND_DROP = Float32(0.3)
comptime POND_FREEBOARD = Float32(0.05)
comptime POND_SHORE = Float32(0.3)
# How far out from a pond's middle the grass is short, as a multiple of
# its radius, so the water shows from eye height.
comptime POND_LAWN = Float32(1.6)
# How far round a lot the ground is bare, and how far further the grass
# comes back, in meters.
comptime APRON = Float32(0.8)
comptime APRON_EDGE = Float32(1.6)
# The linear color of the mountains.
comptime STONE = Vector3(0.036, 0.044, 0.056)
# How wide the step at each rim of a canyon is, in meters.
comptime RIM = Float32(6)
# The linear colors of a cliff: its pale beds, its dark beds, the warm
# stain that water leaves, the moss along its lip, and the woods over it,
# in their shade and where the sky lights them.
comptime ROCK = Vector3(0.200, 0.185, 0.160)
comptime ROCK_DARK = Vector3(0.085, 0.080, 0.075)
comptime OCHRE = Vector3(0.220, 0.150, 0.085)
comptime MOSS = Vector3(0.070, 0.100, 0.030)
comptime WOODS = Vector3(0.022, 0.040, 0.014)
comptime WOODS_LIT = Vector3(0.055, 0.085, 0.026)
# How much higher than its plateau a cliff's rock rises at most, and how
# tall each bed of the rock is, in meters.
comptime CREST = Float32(14)
comptime BED = Float32(9)
# How wide the cell of each crown of the woods along a cliff's crest is,
# and how high the tallest crowns stand over the rock, in meters.
comptime CROWN = Float32(9)
comptime CANOPY = Float32(13)
# The share of a cliff's rows that the foot hidden by the near rim takes.
comptime FOOT_ROWS = Float32(0.25)
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


@fieldwise_init
struct Pond(ImplicitlyCopyable):
    """A round basin in the ground that holds still water.

    The basin's floor lies `depth` below the water. Its inner `POND_FLAT`
    of the radius is flat, and it rises smoothly to the hills at `radius`.
    """

    # The basin's middle, in meters.
    var x: Length
    var z: Length
    # How far out the basin reaches. Zero is no pond.
    var radius: Length
    # How far below the water the basin's floor lies.
    var depth: Length

    def check(self) raises:
        """Refuse a pond that cannot be carved.

        Raises:
            Error: If the middle is further than 10 kilometers, the radius
                is not from 0 to 1 kilometer, or the depth is not from 0 to
                50 meters.
        """
        require_between(
            self.x.to(METER),
            -1.0e4,
            1.0e4,
            "A pond must lie within 10 kilometers",
        )
        require_between(
            self.z.to(METER),
            -1.0e4,
            1.0e4,
            "A pond must lie within 10 kilometers",
        )
        require_between(
            self.radius.to(METER),
            0,
            1000,
            "A pond must be from 0 to 1 kilometer across",
        )
        require_between(
            self.depth.to(METER),
            0,
            50,
            "A pond must be from 0 to 50 meters deep",
        )


def no_pond() -> Pond:
    """Return a pond that carves nothing.

    Returns:
        A pond of no radius.
    """
    return Pond(
        Length(0.0, METER),
        Length(0.0, METER),
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
    # How much of the field is bare dirt, from zero to one.
    var dirt: Float32
    # How wide the trail is. Zero is no trail.
    var trail_width: Length
    # The pond in the ground.
    var pond: Pond

    def __init__(
        out self,
        seed: Int = 3,
        hill_height: Length = Length(1.2, METER),
        hill_length: Length = Length(30.0, METER),
        climb: Float32 = 0.0,
        patch_length: Length = Length(6.0, METER),
        canyon: Canyon = no_canyon(),
        dirt: Float32 = 0.0,
        trail_width: Length = Length(0.0, METER),
        pond: Pond = no_pond(),
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
            dirt: How much of the field is bare dirt, from 0, none, to
                1, about half.
            trail_width: How wide the trail is, from 0, no trail, to 20
                meters.
            pond: The pond in the ground. `no_pond` carves nothing.

        Raises:
            Error: If `check` refuses a value.
        """
        self.seed = seed
        self.hill_height = hill_height
        self.hill_length = hill_length
        self.climb = climb
        self.patch_length = patch_length
        self.canyon = canyon
        self.dirt = dirt
        self.trail_width = trail_width
        self.pond = pond
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
        require_between(self.dirt, 0, 1, "The dirt must be from 0 to 1")
        require_between(
            self.trail_width.to(METER),
            0,
            20,
            "A trail must be from 0 to 20 meters wide",
        )
        self.pond.check()

    def height_at(self, x: Float32, z: Float32) -> Float32:
        """Return the ground's height at a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The height, in meters, the canyon's cut and the pond's basin
            included.
        """
        var hills = self.hills_at(x, z)
        var reach = self.pond.radius.to(METER)
        if reach > 0:
            # No ground outside the basin lies below the water, so the
            # water shows only in it.
            var level = self.water_level()
            hills = max(hills, level + POND_FREEBOARD)
            var dx = x - self.pond.x.to(METER)
            var dz = z - self.pond.z.to(METER)
            var basin = _ramp(reach, reach * POND_FLAT, sqrt(dx * dx + dz * dz))
            var floor = level - self.pond.depth.to(METER)
            hills = hills + (floor - hills) * basin
        return hills + self.canyon.cut(z)

    def wet(self, x: Float32, z: Float32) -> Bool:
        """Return whether a point is under the pond's water or on its bare
        shore.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            True in a pond's basin within `POND_SHORE` above its water, and
            False everywhere else and for ground with no pond.
        """
        return self._in_basin(x, z) and (
            self.height_at(x, z) < self.water_level() + POND_SHORE
        )

    def _in_basin(self, x: Float32, z: Float32) -> Bool:
        """Return whether a point is within the pond's basin."""
        var dx = x - self.pond.x.to(METER)
        var dz = z - self.pond.z.to(METER)
        var reach = self.pond.radius.to(METER)
        return dx * dx + dz * dz < reach * reach

    def water_level(self) -> Float32:
        """Return the height of the pond's still water.

        It lies `POND_DROP` below the hills at the pond's middle. Ground
        that would lie below it outside the basin is raised to
        `POND_FREEBOARD` above it, so the water shows only in the basin. A
        canyon's floor below it holds water too.

        Returns:
            The height, in meters.
        """
        return (
            self.hills_at(self.pond.x.to(METER), self.pond.z.to(METER))
            - POND_DROP
        )

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

    def bare(self, x: Float32, z: Float32) -> Float32:
        """Return how bare the ground is at a point, from zero to one.

        One is dirt with no grass: a patch of dirt, the trail, or the
        pond's bed and its muddy shore, up to `POND_SHORE` above the water.
        The edge of a patch is a few tens of centimeters wide, and the
        trail's width wanders.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The bareness.
        """
        var length = self.patch_length.to(METER) * 2.2
        var raw = layered_noise(x / length + 3.7, z / length, self.seed + 60)
        var start = 0.72 - 0.4 * self.dirt
        var patches = _ramp(start, start + 0.08, raw) * min(
            Float32(1), self.dirt * 20
        )
        var width = self.trail_width.to(METER)
        var course = (
            TRAIL_X
            + TRAIL_DRIFT * (TRAIL_Z - z)
            + TRAIL_WANDER * sin(z / TRAIL_BEND)
        )
        var half = (
            0.5
            * width
            * (0.75 + 0.5 * value_noise(z / 2.5, 0.5, self.seed + 61))
        )
        var trail = (
            TRAIL_WORN
            * (1 - _ramp(half, half + TRAIL_EDGE, abs(x - course)))
            * min(Float32(1), width * 10)
        )
        var shore = Float32(0)
        if self._in_basin(x, z):
            var level = self.water_level()
            shore = _ramp(level + POND_SHORE, level, self.height_at(x, z))
        return max(max(patches, trail), shore)

    def cover(self, x: Float32, z: Float32) -> Float32:
        """Return how thick the grass is at a point, from zero to one.

        Zero is bare ground. Most of the field is near one, with thin
        patches, and none where the ground is bare.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The cover.
        """
        var length = self.patch_length.to(METER)
        var raw = layered_noise(x / length, z / length, self.seed + 10)
        var thick = min(Float32(1), max(Float32(0), (raw - 0.2) * 3.5))
        return thick * (1 - self.bare(x, z))

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
        tall grass stands in islands. Round a pond, out to `POND_LAWN` of
        its radius, the grass is short.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The tallness.
        """
        var length = self.patch_length.to(METER) * 1.6
        var raw = layered_noise(x / length, z / length, self.seed + 40)
        var tall = _ramp(0.36, 0.44, raw)
        var reach = self.pond.radius.to(METER)
        if reach > 0:
            var dx = x - self.pond.x.to(METER)
            var dz = z - self.pond.z.to(METER)
            tall *= _ramp(reach, reach * POND_LAWN, sqrt(dx * dx + dz * dz))
        return tall

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
            Soil where the grass is thin, mottled dirt where the ground is
            bare, the far grass where it is thick, tinted by the straw and
            the poppies.
        """
        var green = FAR_LAWN + (FAR_GRASS - FAR_LAWN) * self.tallness(x, z)
        green = green + (FAR_STRAW - green) * (self.dryness(x, z) * 0.5)
        green = green + (FAR_POPPY - green) * (self.bloom(x, z) * 0.35)
        var mottle = 0.7 * value_noise(
            x / 0.9, z / 0.9, self.seed + 62
        ) + 0.3 * value_noise(x / 0.35, z / 0.35, self.seed + 63)
        var dirt = DIRT + (DIRT_DARK - DIRT) * mottle
        var ground = SOIL + (dirt - SOIL) * self.bare(x, z)
        return ground + (green - ground) * self.cover(x, z)

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


@fieldwise_init
struct Clearing(ImplicitlyCopyable):
    """The shade round a tree's foot, where the grass is thin and the
    ground is leaf litter."""

    # The tree's foot, in meters.
    var x: Float32
    var z: Float32
    # How far out the shade reaches, in meters.
    var radius: Float32


def openness(clearings: List[Clearing], x: Float32, z: Float32) -> Float32:
    """Return how open a point is to the sky, from zero to one.

    The inner `CLEARING_BARE` of a clearing is bare, and the grass comes
    back smoothly out to its edge. Where clearings overlap, the most
    shaded counts.

    Args:
        clearings: The clearings.
        x: The point's x, in meters.
        z: The point's z, in meters.

    Returns:
        One outside every clearing, and zero at a tree's foot.
    """
    var open = Float32(1)
    for index in range(len(clearings)):
        ref clearing = clearings[index]
        var dx = x - clearing.x
        var dz = z - clearing.z
        var reach = clearing.radius
        var far = dx * dx + dz * dz
        if far < reach * reach:
            open = min(open, _ramp(CLEARING_BARE * reach, reach, sqrt(far)))
    return open


def litter_shade(
    mut geometry: BufferGeometry, clearings: List[Clearing], seed: Int
) raises:
    """Brown a ground mesh's colors under its clearings, toward leaf
    litter.

    Args:
        geometry: A ground mesh, with `position` and `color`.
        clearings: The clearings.
        seed: Which mottle the litter has.

    Raises:
        Error: If the geometry has no `position` or no `color`.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    ref colors = geometry.attribute_view(String(COLOR))
    var shaded = List[Float32]()
    shaded.reserve(3 * positions.count())
    for v in range(positions.count()):  # pragma: no branch
        var p = positions.vector3(v)
        var c = colors.vector3(v)
        var shade = 1 - openness(clearings, p.x, p.z)
        var leaf = LITTER * (
            0.75 + 0.5 * value_noise(p.x / 0.6, p.z / 0.6, seed)
        )
        c = c + (leaf - c) * shade
        shaded.append(c.x)
        shaded.append(c.y)
        shaded.append(c.z)
    geometry.set_attribute(COLOR, BufferAttribute(shaded^, 3))


@fieldwise_init
struct Lot(ImplicitlyCopyable):
    """A building's footprint: a rectangle where nothing grows, turned
    about +y, with a bare apron round it."""

    # The middle, in meters.
    var x: Float32
    var z: Float32
    # Half the width along the lot's own x, and half its depth along its
    # own z, in meters.
    var half_width: Float32
    var half_depth: Float32
    # How far the lot is turned about +y, from +x toward -z, in radians.
    var turn: Float32

    def reach(self, x: Float32, z: Float32) -> Float32:
        """Return how far a point is outside the lot.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            Zero inside it, and the distance to its nearest edge outside,
            in meters.
        """
        var dx = x - self.x
        var dz = z - self.z
        var c = cos(self.turn)
        var s = sin(self.turn)
        var across = max(Float32(0), abs(dx * c - dz * s) - self.half_width)
        var along = max(Float32(0), abs(dx * s + dz * c) - self.half_depth)
        return sqrt(across * across + along * along)


def lot_openness(lots: List[Lot], x: Float32, z: Float32) -> Float32:
    """Return how open a point is to growth round the lots.

    The lot and its apron, `APRON` round it, are bare, and the grass comes
    back smoothly over `APRON_EDGE` further.

    Args:
        lots: The lots.
        x: The point's x, in meters.
        z: The point's z, in meters.

    Returns:
        Zero on a lot and its apron, and one clear of them.
    """
    var open = Float32(1)
    for index in range(len(lots)):
        open = min(
            open, _ramp(APRON, APRON + APRON_EDGE, lots[index].reach(x, z))
        )
    return open


def lot_shade(mut geometry: BufferGeometry, lots: List[Lot], seed: Int) raises:
    """Bare a ground mesh's colors round its lots, toward mottled dirt.

    Args:
        geometry: A ground mesh, with `position` and `color`.
        lots: The lots.
        seed: Which mottle the dirt has.

    Raises:
        Error: If the geometry has no `position` or no `color`.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    ref colors = geometry.attribute_view(String(COLOR))
    var bared = List[Float32]()
    bared.reserve(3 * positions.count())
    for v in range(positions.count()):  # pragma: no branch
        var p = positions.vector3(v)
        var c = colors.vector3(v)
        var bare = 1 - lot_openness(lots, p.x, p.z)
        var dirt = DIRT + (DIRT_DARK - DIRT) * value_noise(
            p.x / 0.7, p.z / 0.7, seed
        )
        c = c + (dirt - c) * bare
        bared.append(c.x)
        bared.append(c.y)
        bared.append(c.z)
    geometry.set_attribute(COLOR, BufferAttribute(bared^, 3))


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


def _canopy(x: Float32, seed: Int) -> Float32:
    """Return how high the woods along a cliff's crest stand over its rock
    at `x`, in meters: crowns of many sizes over a low thicket, one crown
    to each cell `CROWN` wide. Most crowns are round, some are the spires
    of firs, and each is lumpy with clumps of leaves."""
    var cell = Int(floor(x / CROWN))
    var top = Float32(0)
    for k in range(cell - 1, cell + 2):  # pragma: no branch
        var middle = (Float32(k) + hash01(k, 0, seed)) * CROWN
        var radius = CROWN * (0.35 + 0.65 * hash01(k, 1, seed))
        var offset = min(Float32(1), abs(x - middle) / radius)
        var lift = 0.35 + 0.65 * hash01(k, 2, seed)
        var round = sqrt(1 - offset * offset)
        var spire = 1.25 * (1 - offset)
        var fir = _ramp(Float32(0.7), Float32(0.75), hash01(k, 3, seed))
        top = max(top, lift * (round + (spire - round) * fir))
    var clumps = 0.85 + 0.3 * value_noise(x / 1.7, 0.5, seed + 1)
    return CANOPY * (0.3 + 0.7 * top) * clumps


def cliff_wall(
    ground: Ground, width: Length, columns: Int, rows: Int, seed: Int
) raises -> BufferGeometry:
    """Return the far wall of a ground's canyon: a cliff face toward +z.

    The face stands just in front of the far rim, so it hides the ground's
    own coarse step there. It runs from the canyon's floor to a crest up
    to `CREST` above the far plateau. It leans back as it rises, juts in
    buttresses, and is cut by flutes. Its rock lies in beds about `BED`
    tall, pale or dark, stained and streaked. Each bed stands out a little
    from the seam over it, and moss grows on its top and along the lip.
    Woods stand on the crest, set back from the lip: round crowns up to
    `CANOPY` over the rock, so the wall's top is ragged as a wood's edge.

    The near rim hides the foot of the wall from the field. So a quarter of
    the rows reach up to just under the near side, and the rest show.

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
    var depth = canyon.depth.to(METER)
    var tall = depth + canyon.rise.to(METER)
    if tall <= 0:
        raise Error("A canyon of no depth and no rise has no wall")
    var face = -canyon.far.to(METER) + RIM + 1
    var half = width.to(METER) * 0.5
    # How much of the wall the hidden rows cover.
    var hidden = max(depth - 4, 0.25 * tall)
    var positions = List[Float32]()
    var colors = List[Float32]()
    var side = columns + 1
    positions.reserve(3 * side * (rows + 1))
    colors.reserve(3 * side * (rows + 1))
    for row in range(rows + 1):  # pragma: no branch
        var v = Float32(row) / Float32(rows)
        for col in range(side):  # pragma: no branch
            var x = -half + 2 * half * Float32(col) / Float32(columns)
            var bottom = ground.hills_at(x, face) - depth
            # The crest rises and falls in long swells, in buttresses and in
            # broken blocks.
            var crest = CREST * (
                0.7 * value_noise(x / 160, 3.5, seed + 3)
                + 0.22 * value_noise(x / 37, 1.5, seed + 6)
                + 0.08 * value_noise(x / 8, 0.5, seed + 7)
            )
            var rock = (
                ground.hills_at(x, face - RIM) + canyon.rise.to(METER) + crest
            )
            var top = rock + _canopy(x, seed + 11)
            var y = bottom + hidden * v / FOOT_ROWS
            if v > FOOT_ROWS:
                y = (
                    bottom
                    + hidden
                    + (top - bottom - hidden)
                    * (v - FOOT_ROWS)
                    / (1 - FOOT_ROWS)
                )
            # How far up the rock the point is, from zero to one.
            var h = min(Float32(1), (y - bottom) / (rock - bottom))
            # Weathering cuts a cliff into vertical flutes and buttresses.
            var buttress = value_noise(x / 14, y / 45, seed)
            var flute = value_noise(x / 2.2, y / 18, seed + 1)
            # The beds dip, wander and thin along the wall. Each one stands
            # out at its foot, and its top steps back to the seam over it.
            var bed = y / BED + 0.8 * value_noise(x / 70, y / 30, seed + 8)
            var within = bed - floor(bed)
            var shelf = _ramp(Float32(0.8), Float32(1), within)
            var jut = tall * (
                (1 - h) * 0.12 + 0.09 * buttress + 0.022 * flute
            ) + 0.5 * (1 - shelf)
            # The woods stand back from the lip.
            var woods = _ramp(rock, rock + 2, y)
            jut = jut * (1 - woods)
            positions.append(x)
            positions.append(y)
            positions.append(face + jut)
            var band = value_noise(x / 60, y / 3, seed + 2)
            var streak = value_noise(x / 2.4, y / 25, seed + 5)
            var stain = value_noise(x / 110, y / 14, seed + 9)
            var c = ROCK + (ROCK_DARK - ROCK) * min(
                Float32(1), max(Float32(0), (band - 0.45) * 3)
            )
            c = c + (OCHRE - c) * 0.6 * _ramp(
                Float32(0.45), Float32(0.75), stain
            )
            # The buttresses stand in the light, and the gullies between
            # them in shadow.
            c = c * (
                0.3
                + 0.3 * h
                + 0.7 * buttress
                + 0.35 * (flute - 0.5)
                + 0.4 * (streak - 0.5)
            )
            # The seam under each bed lies in shadow, and moss takes hold
            # on the ledges and along the lip.
            c = c * (1 - 0.2 * _ramp(Float32(0.1), Float32(0), within))
            var tuft = value_noise(x / 9, y / 4, seed + 10)
            c = c + (MOSS - c) * 0.8 * shelf * _ramp(
                Float32(0.5), Float32(0.8), tuft
            )
            # Scrub clings to the face in patches.
            var scrub = layered_noise(x / 22, y / 10, seed + 13)
            c = c + (WOODS - c) * 0.9 * _ramp(Float32(0.6), Float32(0.7), scrub)
            c = c + (MOSS - c) * _ramp(rock - 2.5, rock, y)
            # The crowns are darker in their shade, low down.
            var leaf = value_noise(x / 3, y / 3, seed + 12)
            var lit = _ramp(rock, top, y) * (0.6 + 0.8 * leaf)
            var crown = WOODS + (WOODS_LIT - WOODS) * min(Float32(1), lit)
            c = c + (crown - c) * woods
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
