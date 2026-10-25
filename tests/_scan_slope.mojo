# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A slope of one-meter voxels with a building on it, for the tests of
`extensions.scan.terrain` and `extensions.scan.parts`.

The grid is 12 by 8 columns and 12 layers. The ground of column i is
solid up to layer `i // 2`, so it rises one layer for each two columns.
On it:

- A building over columns 4 to 6 and rows 2 to 4: a roof in layer 8, and
  walls round it from one layer above the ground of each column to layer
  7. The ground under it is not seen. It has 46 voxels.
- A bump over columns 9 and 10 and rows 1 and 2, four layers above the
  ground.
- A cliff: row 7 is three layers higher than row 6.
- A hole: column 10 of row 6 has no voxel.

With a step of 2 m and a least area of 10 m^2, the slope and the cliff's
row are ground. The roof, 9 m^2, and the bump, 4 m^2, are not.
"""

from extensions.scan.occupancy import OccupancyGrid
from generators.utils import Vec3d
from units.si import Area64, Length64, METER, SQUARE_METER

comptime SLOPE_STEP_M = 2.0
"""The step that joins the slope and parts the roof from it."""
comptime SLOPE_AREA_M2 = 10.0
"""The least area of ground: more than the roof, less than the cliff's row."""


def slope_height(i: Int) -> Int:
    """Return the ground's top layer in column i of the slope.

    Args:
        i: The column's index along x.

    Returns:
        `i // 2`.
    """
    return i // 2


def _in_building(i: Int, j: Int) -> Bool:
    """Return whether a column is under the building's roof.

    Args:
        i: The column's index along x.
        j: The column's index along y.

    Returns:
        Whether i is 4 to 6 and j is 2 to 4.
    """
    return i >= 4 and i <= 6 and j >= 2 and j <= 4


def slope_site() raises -> OccupancyGrid:
    """Return the slope of the module docstring.

    Returns:
        The grid.

    Raises:
        Error: Never.
    """
    var grid = OccupancyGrid(Vec3d(0, 0, 0), Length64(1, METER), 12, 8, 12, 0.5)
    for j in range(8):
        for i in range(12):
            if _in_building(i, j) or (i == 10 and j == 6):
                continue
            var top = slope_height(i)
            if j == 7:
                top += 3
            if (i == 9 or i == 10) and (j == 1 or j == 2):
                top += 4
            for k in range(top + 1):
                grid.weights[grid.index(i, j, k)] = 1
    for j in range(2, 5):
        for i in range(4, 7):
            grid.weights[grid.index(i, j, 8)] = 1
            if i == 5 and j == 3:
                continue
            for k in range(slope_height(i) + 1, 8):
                grid.weights[grid.index(i, j, k)] = 1
    return grid^


def slope_step() -> Length64:
    """Return the slope's step.

    Returns:
        `SLOPE_STEP_M`, in meters.
    """
    return Length64(SLOPE_STEP_M, METER)


def slope_area() -> Area64:
    """Return the slope's least area of ground.

    Returns:
        `SLOPE_AREA_M2`, in square meters.
    """
    return Area64(SLOPE_AREA_M2, SQUARE_METER)
