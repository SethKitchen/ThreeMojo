# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The triangles and the colors of the ground of a landscape.

Each cell of a ring is two triangles with a normal and a color at each
corner. A cell is meadow, rock or snow. Meadow wears the grass texture of the
castle, tinted by the season, the altitude and the wood: dry patches in the
lowland, yellow-green meadow over the treeline, a dark floor under the trees
and a wet dark margin at the water. Rock wears the gravel texture tinted
gray. Snow is a plain white, lit by the sun and the sky like the rest.

A steep cell is rock whatever its altitude, and snow lies on the cells above
the snow line that are not too steep to hold it, with a ragged edge.
"""

from extensions.castle.landscape import Landscape, _Grid
from extensions.castle.parts import Kit, unit_noise
from extensions.visual.mesh import MeshBuilder
from generators.utils import Vec3d
from math.smoothstep import clamped_smoothstep
from std.math import acos, floor, pi

# The mean linear color of the gravel texture, to turn a wanted color of rock
# into the tint that gives it.
comptime _GRAVEL_MEAN = Vec3d(0.236, 0.189, 0.123)
# The mean linear color of the grass texture, and the colors that the meadow
# is wanted in: fresh grass, dry grass in the autumn, and the meadow over the
# treeline.
comptime _GRASS_MEAN = Vec3d(0.0855, 0.1467, 0.0207)
comptime _FRESH = Vec3d(0.07, 0.16, 0.03)
comptime _DRY = Vec3d(0.17, 0.14, 0.05)
comptime _ALPINE = Vec3d(0.14, 0.17, 0.05)
# The wanted linear color of bare rock and of snow.
comptime _ROCK = Vec3d(0.30, 0.28, 0.26)
comptime _SNOW = Vec3d(0.82, 0.85, 0.90)
# The steepest slope, in degrees, where the rock is still covered with turf,
# and where it is all bare.
comptime _TURF_ANGLE = 33.0
comptime _BARE_ANGLE = 47.0


def _field(index: Int) -> Vec3d:
    """Return the color of one of the five fields of the plain: stubble,
    plowed earth, bright pasture, a green crop and hay."""
    if index == 0:
        return Vec3d(0.30, 0.24, 0.09)
    if index == 1:
        return Vec3d(0.15, 0.10, 0.06)
    if index == 2:
        return Vec3d(0.09, 0.21, 0.04)
    if index == 3:
        return Vec3d(0.06, 0.17, 0.04)
    return Vec3d(0.25, 0.21, 0.10)


def _mix(a: Vec3d, b: Vec3d, t: Float64) -> Vec3d:
    """Return the color a share `t` of the way from `a` to `b`."""
    return a * (1.0 - t) + b * t


struct _Surface(Movable):
    """The look of every vertex of a ring: the weight of rock and of snow,
    and the color that each of the three materials would give it."""

    var rock: List[Float64]
    var snow: List[Float64]
    var meadow_color: List[Vec3d]
    var rock_color: List[Vec3d]
    var snow_color: List[Vec3d]

    def __init__(out self, count: Int):
        self.rock = List[Float64](length=count, fill=0.0)
        self.snow = List[Float64](length=count, fill=0.0)
        self.meadow_color = List[Vec3d](length=count, fill=Vec3d(1, 1, 1))
        self.rock_color = List[Vec3d](length=count, fill=Vec3d(1, 1, 1))
        self.snow_color = List[Vec3d](length=count, fill=Vec3d(1, 1, 1))


def _look(land: Landscape, grid: _Grid) raises -> _Surface:
    """Work out the look of every vertex of a ring."""
    var columns = grid.columns
    var surface = _Surface(columns * columns)
    var treeline = land.settings.treeline.value
    var snow_line = land.settings.snow_line.value
    # Noise finer than a few cells only makes the cells speckle.
    var fine = grid.step <= 6.0
    for j in range(columns):  # pragma: no branch
        for i in range(columns):  # pragma: no branch
            var at = j * columns + i
            var x = grid.x0 + Float64(i) * grid.step
            var y = grid.y0 + Float64(j) * grid.step
            var altitude = grid.heights[at] - land.level
            var angle = acos(min(grid.normal(i, j).z, 1.0)) * 180.0 / pi
            # Meadow.
            var mottle = 1.0
            if fine:
                mottle = 0.8 + 0.4 * land.patches(x, y, 9.0, 11)
            var dry = clamped_smoothstep(
                0.55, 0.72, land.patches(x, y, 80.0, 5)
            )
            var color = _mix(_FRESH, _DRY, dry * 0.8)
            # Farmland on the low flat ground, away from the castle: fields.
            var farm = 1.0 - clamped_smoothstep(10.0, 70.0, altitude)
            farm *= clamped_smoothstep(
                70.0, 200.0, land.distance_from_moat(x, y)
            )
            if farm > 0.0:
                # The fields lie on a turned grid, and the noise bends their
                # edges, so no edge runs straight for long.
                var warp_x = 55.0 * (land.patches(x, y, 190.0, 61) - 0.5)
                var warp_y = 55.0 * (land.patches(x, y, 190.0, 67) - 0.5)
                var turned_x = (x + warp_x) * 0.906 - (y + warp_y) * 0.423
                var turned_y = (x + warp_x) * 0.423 + (y + warp_y) * 0.906
                var pick = unit_noise(
                    floor(turned_x / 95.0),
                    floor(turned_y / 70.0),
                    land.settings.seed + 5,
                )
                color = _mix(color, _field(Int(pick * 5.0) % 5), 0.9 * farm)
            var alpine = clamped_smoothstep(
                treeline - 60.0, treeline + 40.0, altitude
            )
            color = _mix(color, _ALPINE, alpine)
            # The floor of a wood is dark, and so is the margin of the water.
            var wood = land.grove(x, y) * (1.0 - alpine)
            wood *= clamped_smoothstep(1.0, 6.0, altitude)
            color = color * (1.0 - 0.45 * wood)
            color = color * (
                0.5 + 0.5 * clamped_smoothstep(-0.3, 1.4, altitude)
            )
            color = color * mottle
            var bare = clamped_smoothstep(_TURF_ANGLE, _BARE_ANGLE, angle)
            # Rock shows through the meadow on a steep slope. A far cell is
            # all meadow material, so the rock is only a color there.
            color = _mix(color, _ROCK, bare)
            # Snow, with a ragged edge, which does not stick to a cliff.
            var edge = (land.patches(x, y, 120.0, 29) - 0.5) * 60.0
            var cover = clamped_smoothstep(
                snow_line - 40.0, snow_line + 40.0, altitude + edge
            )
            var snow = cover * (1.0 - clamped_smoothstep(46.0, 58.0, angle))
            var white = _SNOW * (0.92 + 0.16 * land.patches(x, y, 30.0, 23))
            surface.snow[at] = snow
            surface.snow_color[at] = white
            # The meadow and the rock take the white of the snow at a vertex
            # that the snow reaches, so that a cell of meadow or of rock at
            # the edge of the snow fades into it and is not a square.
            color = _mix(color, white, snow)
            surface.meadow_color[at] = Vec3d(
                color.x / _GRASS_MEAN.x,
                color.y / _GRASS_MEAN.y,
                color.z / _GRASS_MEAN.z,
            )
            # Rock.
            var tone = 1.0
            if fine:
                tone = 0.7 + 0.6 * land.patches(x, y, 14.0, 17)
            var wanted = _mix(_ROCK * tone, white, snow * 0.85)
            surface.rock_color[at] = Vec3d(
                wanted.x / _GRAVEL_MEAN.x,
                wanted.y / _GRAVEL_MEAN.y,
                wanted.z / _GRAVEL_MEAN.z,
            )
            surface.rock[at] = bare
    return surface^


def add_ground(land: Landscape, mut kit: Kit) raises:
    """Add the triangles of the whole ground to a kit.

    The meadow goes to the lawn builder, the rock to the gravel builder and
    the snow to the wood builder, which has no texture.

    Args:
        land: The landscape.
        kit: The builders that receive the triangles.

    Raises:
        Error: If a noise coordinate is not finite.
    """
    for ring in range(len(land.rings)):  # pragma: no branch
        ref grid = land.rings[ring]
        var surface = _look(land, grid)
        var columns = grid.columns
        for j in range(columns - 1):  # pragma: no branch
            for i in range(columns - 1):  # pragma: no branch
                var x = grid.x0 + (Float64(i) + 0.5) * grid.step
                var y = grid.y0 + (Float64(j) + 0.5) * grid.step
                if (
                    abs(x - land.middle_x) < grid.hole
                    and abs(y - land.middle_y) < grid.hole
                ):
                    continue
                var ids: List[Int] = [
                    j * columns + i,
                    j * columns + i + 1,
                    (j + 1) * columns + i + 1,
                    (j + 1) * columns + i,
                ]
                # The diagonal turns on every other cell, as `Landscape` has it.
                var flipped = (i + j) % 2 == 1
                var snow = 0.0
                var rock = 0.0
                for corner in range(4):
                    snow += surface.snow[ids[corner]] / 4.0
                    rock += surface.rock[ids[corner]] / 4.0
                var points = List[Vec3d]()
                var normals = List[Vec3d]()
                for corner in range(4):
                    var ci = i + (1 if corner == 1 or corner == 2 else 0)
                    var cj = j + (1 if corner >= 2 else 0)
                    points.append(
                        Vec3d(
                            grid.x0 + Float64(ci) * grid.step,
                            grid.y0 + Float64(cj) * grid.step,
                            grid.heights[ids[corner]],
                        )
                    )
                    normals.append(grid.normal(ci, cj))
                # The cells of a far ring are all meadow material, with
                # the rock and the snow in their colors, so that none stands
                # out as a square of another texture.
                var near = ring < 2
                if near and snow > 0.3:
                    _cell(
                        kit.wood,
                        points,
                        normals,
                        surface.snow_color,
                        ids,
                        flipped,
                    )
                elif near and rock > 0.5:
                    _cell(
                        kit.gravel,
                        points,
                        normals,
                        surface.rock_color,
                        ids,
                        flipped,
                    )
                else:
                    _cell(
                        kit.lawn,
                        points,
                        normals,
                        surface.meadow_color,
                        ids,
                        flipped,
                    )


def _cell(
    mut mesh: MeshBuilder,
    points: List[Vec3d],
    normals: List[Vec3d],
    colors: List[Vec3d],
    ids: List[Int],
    flipped: Bool,
):
    """Add the two triangles of a cell: a b c and a c d, or, if the diagonal
    is turned, a b d and b c d."""
    if flipped:
        mesh.smooth_triangle(
            points[0],
            points[1],
            points[3],
            normals[0],
            normals[1],
            normals[3],
            colors[ids[0]],
            colors[ids[1]],
            colors[ids[3]],
        )
        mesh.smooth_triangle(
            points[1],
            points[2],
            points[3],
            normals[1],
            normals[2],
            normals[3],
            colors[ids[1]],
            colors[ids[2]],
            colors[ids[3]],
        )
        return
    mesh.smooth_triangle(
        points[0],
        points[1],
        points[2],
        normals[0],
        normals[1],
        normals[2],
        colors[ids[0]],
        colors[ids[1]],
        colors[ids[2]],
    )
    mesh.smooth_triangle(
        points[0],
        points[2],
        points[3],
        normals[0],
        normals[2],
        normals[3],
        colors[ids[0]],
        colors[ids[2]],
        colors[ids[3]],
    )
