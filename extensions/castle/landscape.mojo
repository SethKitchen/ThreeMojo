# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The castle in a landscape: one ground that runs from the meadow of the
castle up into mountains.

The ground has two sources and one height. Round the moat it is the ground of
the castle, `ground_height`, so the bank, the moat bed and the island are
what the plan says. Farther out it is the mountain range of
`generators.terrain`, lowered so that its lowest ground is the plain of the
castle. A weight rises from zero to one with the distance from the moat, and
the height is the castle's ground plus the weight times the relief of the
mountains. So the mountains start where the meadow ends, and nothing jumps.

Where the relief is below the plain it sinks to a lake bed, and the water of
the moat is the water of the lake: the one plane of Clearwater at the level
of the moat floods every basin that lies under it.

The ground is drawn as four square rings that step from fine to coarse, 1 m
cells round the castle and cells 80 times wider at the horizon. The height at
the edge of a fine ring is read from the coarse ring beside it, so that two
rings meet with no crack. `Landscape.height` reads the same triangles that
are drawn, so a tree planted with it stands on the ground.

The material of the ground follows the slope and the altitude: meadow, bare
rock on steep slopes, snow high up, and a wet dark margin at the water.
"""

from extensions.castle.parts import Kit, unit_noise
from extensions.castle.plan import (
    CastlePlan,
    Point,
    convex_hull,
    distance_to_outline,
    point,
)
from extensions.castle.render import ground_height
from generators.terrain import TerrainGenerator, TerrainParameters
from generators.utils import Vec3d
from math.noise import ImprovedNoise
from math.smoothstep import clamped_smoothstep
from std.math import cos, exp, floor, isfinite, pi, sin, sqrt
from units.si import InverseLength, Length, Length64, METER, PER_METER

# The number of rings, and the step of each in units of the near step.
comptime _RINGS = 4
comptime _STEP_FACTOR_1 = 5.0
comptime _STEP_FACTOR_2 = 20.0
comptime _STEP_FACTOR_3 = 80.0
# Past this distance from the moat the ground has no ripple.
comptime _RIPPLE_REACH = 40.0
# The margin round the moat that the finest ring covers, in meters.
comptime _NEAR_MARGIN = 75.0


@fieldwise_init
struct LandscapeSettings(ImplicitlyCopyable):
    """The choices of a landscape."""

    # Where the mountains' random numbers start.
    var seed: Int
    # The height from the lowest ground to the peaks.
    var relief: Length64
    # The width of a mountain's footprint.
    var footprint: Length64
    # The width of a range, and of a basin between ranges.
    var range: Length64
    # The octaves of noise of the mountains.
    var octaves: Int
    # The share of the mountains' ground that is at or under the plain, from
    # 0 up to 1. A larger share leaves more lakes.
    var plain_share: Float64
    # The depth that the lowest basins sink under the plain.
    var lake_depth: Length64
    # Inside this distance from the moat the ground is the castle's own.
    var plain_radius: Length64
    # Beyond this distance from the moat the mountains stand full height.
    var hills_radius: Length64
    # The cell of the finest ring. The other rings are 5, 20 and 80 times
    # wider.
    var near_step: Length64
    # How far the ground runs from the middle of the castle.
    var reach: Length64
    # The cells a side of the baked mountains.
    var segments: Int
    # The altitude over the water above which no tree grows.
    var treeline: Length64
    # The altitude over the water above which snow lies.
    var snow_line: Length64
    # How fast the air thickens with distance, per meter: the fog of the
    # scene, which is the color of the horizon.
    var haze: Float64

    def check(self) raises:
        """Refuse settings that cannot make a landscape.

        Raises:
            Error: If a length is not positive and finite, the radii are not
                in order, the share is not from 0 to 1, the octave or segment
                count is below one, or the treeline is above the snow line.
        """
        var lengths = [
            self.relief.value,
            self.footprint.value,
            self.range.value,
            self.lake_depth.value,
            self.plain_radius.value,
            self.hills_radius.value,
            self.near_step.value,
            self.reach.value,
            self.treeline.value,
            self.snow_line.value,
        ]
        for at in range(len(lengths)):  # pragma: no branch
            if not (isfinite(lengths[at]) and lengths[at] > 0.0):
                raise Error("The sizes of a landscape must be positive finite")
        if not (self.plain_radius.value < self.hills_radius.value):
            raise Error("The hills must start past the plain")
        if not (self.plain_share >= 0.0 and self.plain_share <= 1.0):
            raise Error("The share of plain must be from 0 to 1")
        if self.octaves < 1 or self.segments < 1:
            raise Error("A landscape needs an octave and a segment")
        if not (self.treeline.value < self.snow_line.value):
            raise Error("The treeline must lie under the snow line")
        if not (isfinite(self.haze) and self.haze >= 0.0):
            raise Error("The haze must be zero or more and finite")


def default_landscape() -> LandscapeSettings:
    """Return the landscape of a picture made to be looked at.

    Returns:
        Mountains 1500 m high with footprints of 3.2 km in ranges 7 km wide,
        12 m deep lakes, a plain 150 m round the moat that gives way to hills
        by 700 m, 1 m
        cells at the castle, a reach of 9.6 km, a treeline at 260 m and snow
        from 400 m over the water, and a haze of 0.00022 a meter.
    """
    return LandscapeSettings(
        7,
        Length64(1500.0, METER),
        Length64(3200.0, METER),
        Length64(7000.0, METER),
        7,
        0.10,
        Length64(12.0, METER),
        Length64(150.0, METER),
        Length64(700.0, METER),
        Length64(1.0, METER),
        Length64(9600.0, METER),
        800,
        Length64(260.0, METER),
        Length64(400.0, METER),
        0.00022,
    )


struct _Grid(Copyable, Movable):
    """One square ring of the ground: heights on a grid, and the hole in its
    middle that a finer ring fills."""

    # The corner of the grid and its spacing.
    var x0: Float64
    var y0: Float64
    var step: Float64
    var columns: Int
    # The half width of the ring, and of the square hole in its middle, which
    # is zero for the finest ring.
    var half: Float64
    var hole: Float64
    var heights: List[Float64]

    def __init__(
        out self,
        x0: Float64,
        y0: Float64,
        step: Float64,
        columns: Int,
        half: Float64,
        hole: Float64,
    ):
        self.x0 = x0
        self.y0 = y0
        self.step = step
        self.columns = columns
        self.half = half
        self.hole = hole
        self.heights = List[Float64](length=columns * columns, fill=0.0)

    def _cell(
        self, x: Float64, y: Float64
    ) -> Tuple[Int, Int, Float64, Float64]:
        """Return the cell under a point, held to the grid, and the place in
        it from zero to one along each side."""
        var gx = min(
            max((x - self.x0) / self.step, 0.0), Float64(self.columns - 1)
        )
        var gy = min(
            max((y - self.y0) / self.step, 0.0), Float64(self.columns - 1)
        )
        var i = min(Int(floor(gx)), self.columns - 2)
        var j = min(Int(floor(gy)), self.columns - 2)
        return (i, j, gx - Float64(i), gy - Float64(j))

    def sample(self, x: Float64, y: Float64) -> Float64:
        """Return the height of the triangles of the grid at a point.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The height. A point off the grid reads the nearest edge.
        """
        var cell = self._cell(x, y)
        var i = cell[0]
        var j = cell[1]
        var a = self.heights[j * self.columns + i]
        var b = self.heights[j * self.columns + i + 1]
        var c = self.heights[(j + 1) * self.columns + i + 1]
        var d = self.heights[(j + 1) * self.columns + i]
        # The cell is two triangles, as it is drawn. The diagonal turns on
        # every other cell, so no ridge runs along it.
        if (i + j) % 2 == 0:
            if cell[2] >= cell[3]:
                return a + (b - a) * cell[2] + (c - b) * cell[3]
            return a + (c - d) * cell[2] + (d - a) * cell[3]
        if cell[2] + cell[3] <= 1.0:
            return a + (b - a) * cell[2] + (d - a) * cell[3]
        return c + (d - c) * (1.0 - cell[2]) + (b - c) * (1.0 - cell[3])

    def flatness(self, x: Float64, y: Float64) -> Float64:
        """Return how flat the triangle under a point is.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The vertical component of its unit normal: one on level ground
            and toward zero on a cliff.
        """
        var cell = self._cell(x, y)
        var i = cell[0]
        var j = cell[1]
        var a = self.heights[j * self.columns + i]
        var b = self.heights[j * self.columns + i + 1]
        var c = self.heights[(j + 1) * self.columns + i + 1]
        var d = self.heights[(j + 1) * self.columns + i]
        var rise_x: Float64
        var rise_y: Float64
        if (i + j) % 2 == 0:
            if cell[2] >= cell[3]:
                rise_x = (b - a) / self.step
                rise_y = (c - b) / self.step
            else:
                rise_x = (c - d) / self.step
                rise_y = (d - a) / self.step
        elif cell[2] + cell[3] <= 1.0:
            rise_x = (b - a) / self.step
            rise_y = (d - a) / self.step
        else:
            rise_x = (c - d) / self.step
            rise_y = (c - b) / self.step
        return 1.0 / sqrt(1.0 + rise_x * rise_x + rise_y * rise_y)

    def normal(self, i: Int, j: Int) -> Vec3d:
        """Return the unit normal of the surface at a vertex.

        Args:
            i: The column of the vertex.
            j: The row of the vertex.

        Returns:
            The normal, by central differences, pointing up.
        """
        var il = max(i - 1, 0)
        var ir = min(i + 1, self.columns - 1)
        var jd = max(j - 1, 0)
        var ju = min(j + 1, self.columns - 1)
        var dzdx = (
            self.heights[j * self.columns + ir]
            - self.heights[j * self.columns + il]
        ) / (Float64(ir - il) * self.step)
        var dzdy = (
            self.heights[ju * self.columns + i]
            - self.heights[jd * self.columns + i]
        ) / (Float64(ju - jd) * self.step)
        return Vec3d(-dzdx, -dzdy, 1).normalized()


struct Landscape(Movable):
    """The ground of a castle in its landscape: its heights, and the levels
    that the water, the trees and the snow keep to."""

    var settings: LandscapeSettings
    # The middle of the ground, in the plan.
    var middle_x: Float64
    var middle_y: Float64
    # The height of the water, and of the meadow, over the island.
    var level: Float64
    var ground: Float64
    # The rings, finest first.
    var rings: List[_Grid]
    # The outline of the moat, to measure the distance from it.
    var moat: List[Point]
    # The noise that patches the meadow and the groves.
    var noise: ImprovedNoise

    def __init__(
        out self,
        settings: LandscapeSettings,
        middle_x: Float64,
        middle_y: Float64,
        level: Float64,
        ground: Float64,
        var rings: List[_Grid],
        var moat: List[Point],
    ):
        self.settings = settings
        self.middle_x = middle_x
        self.middle_y = middle_y
        self.level = level
        self.ground = ground
        self.rings = rings^
        self.moat = moat^
        self.noise = ImprovedNoise()

    def ring_at(self, x: Float64, y: Float64) -> Int:
        """Return which ring draws the ground at a point.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The index of the finest ring that has a cell under the point.
        """
        var away = max(abs(x - self.middle_x), abs(y - self.middle_y))
        for at in range(len(self.rings)):  # pragma: no branch
            if away < self.rings[at].half:
                return at
        return len(self.rings) - 1

    def height(self, x: Float64, y: Float64) -> Float64:
        """Return the height of the drawn ground at a point.

        Args:
            x: The east coordinate, in meters in the plan.
            y: The north coordinate.

        Returns:
            The height over the island, in meters.
        """
        return self.rings[self.ring_at(x, y)].sample(x, y)

    def flatness(self, x: Float64, y: Float64) -> Float64:
        """Return how flat the drawn ground is at a point.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The vertical component of the unit normal: one on level ground
            and toward zero on a cliff.
        """
        return self.rings[self.ring_at(x, y)].flatness(x, y)

    def altitude(self, x: Float64, y: Float64) -> Float64:
        """Return the height of the ground over the water.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The altitude, in meters. It is negative under water.
        """
        return self.height(x, y) - self.level

    def distance_from_moat(self, x: Float64, y: Float64) raises -> Float64:
        """Return how far a point is from the edge of the moat.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            The distance, in meters.

        Raises:
            Error: If the moat has fewer than three corners.
        """
        return distance_to_outline(self.moat, point(x, y)).value

    def patches(
        self, x: Float64, y: Float64, scale: Float64, seed: Int
    ) raises -> Float64:
        """Return slow noise that breaks the ground into patches.

        Args:
            x: The east coordinate.
            y: The north coordinate.
            scale: The width of a patch, in meters.
            seed: Which noise.

        Returns:
            A number from 0 to 1.

        Raises:
            Error: If a coordinate is not finite.
        """
        var first = self.noise.noise(
            x / scale + Float64(seed) * 17.3,
            y / scale + Float64(seed) * 5.1,
            0.37,
        )
        var second = self.noise.noise(
            x * 2.1 / scale + 31.7, y * 2.1 / scale + 8.9, 0.71 + Float64(seed)
        )
        var mixed = (first * 0.7 + second * 0.3) * 1.6
        return min(max(0.5 + 0.5 * mixed, 0.0), 1.0)

    def grove(self, x: Float64, y: Float64) raises -> Float64:
        """Return how thick the wood stands at a point: groves and clearings.

        Args:
            x: The east coordinate.
            y: The north coordinate.

        Returns:
            A number from 0, a clearing, to 1, a thick wood.

        Raises:
            Error: If a coordinate is not finite.
        """
        return clamped_smoothstep(0.38, 0.62, self.patches(x, y, 260.0, 3))


def _relief(
    terrain: TerrainGenerator,
    plain: Float64,
    depth: Float64,
    x: Float64,
    y: Float64,
) raises -> Float64:
    """Return the height of the mountains over the plain at a point of the
    baked patch. Under the plain it sinks to a lake bed no deeper than
    `depth`."""
    var rise = terrain.height_at(x, y) - plain
    if rise < 0.0:
        return -depth * (1.0 - exp(rise / depth))
    return rise


def _ring_sizes(
    settings: LandscapeSettings, half_near: Float64
) raises -> List[Float64]:
    """Return the half width of each of the four rings, finest first."""
    var unit = settings.near_step.value
    var coarse = _STEP_FACTOR_3 * unit
    var outer = Float64(Int(floor(settings.reach.value / coarse + 0.999999)))
    outer *= coarse
    var near_step = _STEP_FACTOR_1 * unit
    var near = Float64(Int(floor(half_near / near_step + 0.999999))) * near_step
    var sizes = List[Float64]()
    sizes.append(near)
    sizes.append(outer / 16.0)
    sizes.append(outer / 4.0)
    sizes.append(outer)
    if not (near < sizes[1]):
        raise Error(
            "The reach is too short: the ground of the castle does not fit"
            " the finest ring"
        )
    return sizes^


def build_landscape(
    plan: CastlePlan, settings: LandscapeSettings
) raises -> Landscape:
    """Lay the ground of a castle in a landscape.

    It bakes the mountains, finds the plain, and fills the four rings with
    heights. The weight of the mountains is zero inside `plain_radius` of
    the moat and one past `hills_radius`.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices of the landscape.

    Returns:
        The landscape.

    Raises:
        Error: If the plan or the settings are refused, or the reach is too
            short to hold the ground of the castle.
    """
    plan.check()
    settings.check()
    var hull = convex_hull(plan.moat.outline)
    var low_x = Float64(1.0e30)
    var low_y = Float64(1.0e30)
    var high_x = Float64(-1.0e30)
    var high_y = Float64(-1.0e30)
    for corner in plan.moat.outline:  # pragma: no branch
        low_x = min(low_x, corner.x.value)
        low_y = min(low_y, corner.y.value)
        high_x = max(high_x, corner.x.value)
        high_y = max(high_y, corner.y.value)
    var middle_x = (low_x + high_x) / 2.0
    var middle_y = (low_y + high_y) / 2.0
    var half_near = max(high_x - low_x, high_y - low_y) / 2.0 + _NEAR_MARGIN
    var sizes = _ring_sizes(settings, half_near)
    var parameters = TerrainParameters()
    parameters.seed = settings.seed
    parameters.size = Length(Float32(2.0 * sizes[3]), METER)
    parameters.segments = settings.segments
    parameters.height_scale = Length(Float32(settings.relief.value), METER)
    parameters.frequency = InverseLength(
        Float32(1.0 / settings.footprint.value), PER_METER
    )
    parameters.octaves = settings.octaves
    var noise = ImprovedNoise()
    var mountains = TerrainGenerator(parameters^)
    _ = mountains.build()
    var sorted_heights = mountains.heights.copy()
    sort(sorted_heights)
    var rank = Int(settings.plain_share * Float64(len(sorted_heights)))
    var plain = Float64(sorted_heights[min(rank, len(sorted_heights) - 1)])
    var ground = plan.ground_level.value - plan.island_level.value
    var level = plan.moat.water_level.value - plan.island_level.value
    var unit = settings.near_step.value
    var steps: List[Float64] = [
        unit,
        _STEP_FACTOR_1 * unit,
        _STEP_FACTOR_2 * unit,
        _STEP_FACTOR_3 * unit,
    ]
    var rings = List[_Grid]()
    for ring in range(_RINGS):  # pragma: no branch
        var half = sizes[ring]
        var step = steps[ring]
        var columns = Int(2.0 * half / step) + 1
        var hole = 0.0 if ring == 0 else sizes[ring - 1]
        var grid = _Grid(
            middle_x - half, middle_y - half, step, columns, half, hole
        )
        for j in range(columns):  # pragma: no branch
            for i in range(columns):  # pragma: no branch
                var x = grid.x0 + Float64(i) * step
                var y = grid.y0 + Float64(j) * step
                var at = point(x, y)
                var away = distance_to_outline(plan.moat.outline, at).value
                var base = ground
                if away < _RIPPLE_REACH:
                    base = ground_height(plan, hull, at)
                var weight = clamped_smoothstep(
                    settings.plain_radius.value,
                    settings.hills_radius.value,
                    away,
                )
                var raised = 0.0
                if weight > 0.0:
                    # Ranges and basins: the mountains stand tall where a
                    # slow noise is high, and sink to rolling hills where it
                    # is low.
                    var slow = noise.noise(
                        (x - middle_x) / settings.range.value
                        + 3.7
                        + Float64(settings.seed) * 1.91,
                        (y - middle_y) / settings.range.value
                        + 9.1
                        + Float64(settings.seed) * 0.77,
                        0.5,
                    )
                    var massif = clamped_smoothstep(-0.25, 0.45, slow)
                    # The land rolls near the castle and heaves far off.
                    var grow = 0.35 + 1.65 * clamped_smoothstep(
                        1200.0, 6500.0, away
                    )
                    # The coarse rings take the mean of four heights of the
                    # cell, so a ridge narrower than the cell does not alias.
                    var spread = 0.0 if ring < 2 else step * 0.3
                    var rise = 0.0
                    for corner in range(4):  # pragma: no branch
                        var shift_x = spread * (
                            1.0 if corner % 2 == 0 else -1.0
                        )
                        var shift_y = spread * (1.0 if corner < 2 else -1.0)
                        rise += _relief(
                            mountains,
                            plain,
                            settings.lake_depth.value,
                            x - middle_x + shift_x,
                            y - middle_y + shift_y,
                        )
                    raised = weight * grow * (0.22 + 0.78 * massif) * rise / 4.0
                grid.heights[j * columns + i] = base + raised
        rings.append(grid^)
    # A fine ring meets the coarse ring round it along an edge. Its vertices
    # on that edge are put on the coarse ring's triangles, so no crack opens.
    for ring in range(_RINGS - 1):  # pragma: no branch
        ref fine = rings[ring]
        ref coarse = rings[ring + 1]
        var width = 2.0 * fine.half
        for k in range(fine.columns):  # pragma: no branch
            var along = fine.x0 + Float64(k) * fine.step
            var across = fine.y0 + Float64(k) * fine.step
            fine.heights[k] = coarse.sample(along, fine.y0)
            fine.heights[(fine.columns - 1) * fine.columns + k] = coarse.sample(
                along, fine.y0 + width
            )
            fine.heights[k * fine.columns] = coarse.sample(fine.x0, across)
            fine.heights[k * fine.columns + fine.columns - 1] = coarse.sample(
                fine.x0 + width, across
            )
    return Landscape(
        settings,
        middle_x,
        middle_y,
        level,
        ground,
        rings^,
        plan.moat.outline.copy(),
    )


def find_site(
    land: Landscape,
    east: Float64,
    north: Float64,
    radius: Float64,
    clearance: Float64,
) raises -> Point:
    """Find open, level, dry ground for a building, as near a place as it
    can be.

    The ground must be level and above the water over the whole round of the
    building, and clear of the moat.

    Args:
        land: The landscape.
        east: The east coordinate of the place that is wanted.
        north: The north coordinate.
        radius: How far the building reaches from its middle, in meters.
        clearance: How far the middle must stand from the edge of the moat,
            in meters.

    Returns:
        The middle of the nearest site.

    Raises:
        Error: If no site lies within 600 m of the place.
    """
    var spacing = 15.0
    var rings = Int(600.0 / spacing)
    for ring in range(rings):  # pragma: no branch
        var reach = Float64(ring) * spacing
        var around = max(1, Int(2.0 * pi * reach / spacing))
        for step in range(around):  # pragma: no branch
            var angle = 2.0 * pi * Float64(step) / Float64(around)
            var x = east + reach * cos(angle)
            var y = north + reach * sin(angle)
            if land.distance_from_moat(x, y) < clearance:
                continue
            var level = True
            for k in range(9):  # pragma: no branch
                var probe_angle = 2.0 * pi * Float64(k) / 8.0
                var share = 0.0 if k == 8 else radius
                var px = x + share * cos(probe_angle)
                var py = y + share * sin(probe_angle)
                var altitude = land.altitude(px, py)
                if (
                    land.flatness(px, py) < 0.985
                    or altitude < 2.0
                    or altitude > 25.0
                ):
                    level = False
            if level:
                return point(x, y)
    raise Error("No level dry ground for a building lies near that place")
