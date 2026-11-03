# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An Alcubierre warp bubble, analyzed as WarpFactory analyzes it.

    mojo run -I . examples/warp_drive.mojo [path.png]

The page is Warp drives. The bubble moves along x at half the speed of
light. The three panels cut the plane z = 0 through its center:

1. The energy density that the Eulerian observer measures. Red is
   negative.
2. The null energy condition. Red violates it.
3. The expansion of the Eulerian observers. Blue grows and red shrinks.

Each panel spans its own range of values, with white at zero. The two
points next to each edge are left out: there the stencils copy the
nearest derivative they can reach.
"""

from tools._example_output import example_destination, blit

from extensions.warp.conditions import energy_condition
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import NULL_ENERGY, T_AXIS, Z_AXIS
from extensions.warp.metrics import alcubierre_comoving
from extensions.warp.plot import PlaneSlice, draw_plane, slice_plane
from extensions.warp.quantities import fraction_of_light
from extensions.warp.scalars import metric_scalars
from extensions.warp.solver import stress_energy
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from units.si import Duration64, InverseLength64, Length64

comptime DEFAULT_OUTPUT = "out/warp-drive.png"
# Points along x and y. Five along z, the fewest the stencils need.
comptime SIDE = 96
comptime SCALE = 4
comptime GAP = 8
# The points next to each edge, where the stencils do not reach.
comptime EDGE = 2


def _inner(plane: PlaneSlice) -> PlaneSlice:
    """Return the plane without the points next to its edges."""
    var columns = plane.columns - 2 * EDGE
    var rows = plane.rows - 2 * EDGE
    var values = List[Float64](capacity=columns * rows)
    for row in range(rows):
        for column in range(columns):
            values.append(plane.at(column + EDGE, row + EDGE))
    return PlaneSlice(columns, rows, values^)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var grid = SpacetimeGrid(
        1,
        SIDE,
        SIDE,
        5,
        Duration64(1.0),
        Length64(0.125),
        Length64(0.125),
        Length64(0.125),
    )
    var metric = alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(3.0),
        InverseLength64(2.0),
    )
    var energy = stress_energy(metric)
    var eulerian = to_eulerian(energy, metric)
    var null = energy_condition(eulerian, metric, NULL_ENERGY, 50)
    var scalars = metric_scalars(metric)
    var fields = List[List[Float64]]()
    fields.append(eulerian.tensor.component(0, 0))
    fields.append(null.values.copy())
    fields.append(scalars.expansion.copy())
    var side = (SIDE - 2 * EDGE) * SCALE
    var sheet = Framebuffer(
        3 * side + 4 * GAP, side + 2 * GAP, Color(32, 34, 40)
    )
    for panel in range(3):
        var plane = slice_plane(fields[panel], grid, T_AXIS, 0, Z_AXIS, 2)
        blit(
            sheet,
            draw_plane(_inner(plane), SCALE),
            GAP + panel * (side + GAP),
            GAP,
        )
    Path(destination).write_bytes(encode(sheet))
    print("Wrote", destination)
    print(
        "Most violating null value:",
        null.worst().value,
        "J/m^3 on",
        null.violations(),
        "of",
        grid.points(),
        "points",
    )
