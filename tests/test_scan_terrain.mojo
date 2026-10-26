# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.terrain`, the ground of a scanned place as a
surface.

The site is the slope of `tests/_scan_slope.mojo`: a building, a bump, a
cliff and a hole on ground that rises one layer for each two columns.
"""

from extensions.scan.occupancy import OccupancyGrid
from extensions.scan.terrain import (
    GroundSurface,
    TerrainOptions,
    column_tops,
    flat_ground,
    ground_grid,
    terrain_ground,
)
from generators.utils import Vec3d
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from tests._scan_slope import (
    slope_area,
    slope_height,
    slope_site,
    slope_step,
)
from units.si import Area64, Length64, METER, SQUARE_METER


def _expected(i: Int, j: Int) -> Int:
    """Return the ground layer of a column of the slope.

    Args:
        i: The column's index along x.
        j: The column's index along y.

    Returns:
        The layer that `terrain_ground` must give it.
    """
    # Under the building: the lowest of the nearest ground.
    var building: List[Int] = [1, 2, 3, 1, 1, 3, 1, 2, 3]
    if i >= 4 and i <= 6 and j >= 2 and j <= 4:
        return building[(j - 2) * 3 + (i - 4)]
    # The cliff's row is ground, three layers up.
    if j == 7:
        return slope_height(i) + 3
    # The hole takes the lowest of the four columns round it.
    if i == 10 and j == 6:
        return 4
    # The bump and the slope have the slope's height.
    return slope_height(i)


def test_the_tops_are_the_highest_solid_voxels() raises:
    """A roof, a bump, the ground and a hole."""
    var grid = slope_site()
    var tops = column_tops(grid)
    assert_equal(tops[3 * 12 + 5], 8)
    assert_equal(tops[2 * 12 + 4], 8)
    assert_equal(tops[1 * 12 + 10], 9)
    assert_equal(tops[0], 0)
    assert_equal(tops[7 * 12 + 11], 8)
    assert_equal(tops[6 * 12 + 10], -1)


def test_the_ground_goes_on_under_the_building() raises:
    """The slope and the cliff's row keep their tops; the roof, the bump
    and the hole take the lowest of the nearest ground."""
    var grid = slope_site()
    var ground = terrain_ground(
        grid, TerrainOptions(slope_step(), slope_area())
    )
    assert_equal(ground.nx, 12)
    assert_equal(ground.ny, 8)
    assert_equal(ground.tolerance, 2)
    for j in range(8):
        for i in range(12):
            assert_equal(ground.layer(i, j), _expected(i, j))
    ground.check(grid)


def test_with_no_large_surface_there_is_no_ground() raises:
    """No surface reaches the least area, so no voxel is ground, and a
    part of a step is a whole layer less."""
    var grid = slope_site()
    var ground = terrain_ground(
        grid,
        TerrainOptions(Length64(2.5, METER), Area64(1000, SQUARE_METER)),
    )
    assert_equal(ground.tolerance, 2)
    for layer in ground.layers:
        assert_equal(layer, -1)


def test_a_flat_ground_has_one_layer() raises:
    """Each column has the layer, and no tolerance."""
    var grid = slope_site()
    var ground = flat_ground(grid, 3)
    assert_equal(len(ground.layers), 96)
    assert_equal(ground.layer(11, 7), 3)
    assert_equal(ground.tolerance, 0)
    assert_equal(flat_ground(grid, -1).layer(0, 0), -1)
    assert_equal(flat_ground(grid, 11).layer(0, 0), 11)


def test_the_ground_as_a_grid_is_solid_up_to_its_layers() raises:
    """Each column is solid up to its layer and empty above it."""
    var grid = slope_site()
    var ground = terrain_ground(
        grid, TerrainOptions(slope_step(), slope_area())
    )
    var solid = ground_grid(grid, ground)
    assert_equal(solid.nx, 12)
    assert_equal(solid.nz, 12)
    assert_equal(solid.solid_weight, grid.solid_weight)
    var count = 0
    for j in range(8):
        for i in range(12):
            count += _expected(i, j) + 1
    assert_equal(solid.solid_count(), count)
    assert_equal(solid.is_solid(5, 3, 1), True)
    assert_equal(solid.is_solid(5, 3, 2), False)
    assert_equal(solid.weights[solid.index(0, 0, 0)], 0.5)


def test_what_cannot_be_a_ground_is_refused() raises:
    """Steps, areas, counts, layers, tolerances and other grids."""
    var grid = slope_site()
    for bad in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        with assert_raises(contains="the step must be positive"):
            _ = terrain_ground(
                grid, TerrainOptions(Length64(bad, METER), slope_area())
            )
        with assert_raises(contains="the least area must be positive"):
            _ = terrain_ground(
                grid, TerrainOptions(slope_step(), Area64(bad, SQUARE_METER))
            )
    with assert_raises(contains="one column at least each way"):
        _ = GroundSurface(0, 1, [0], 0)
    with assert_raises(contains="one column at least each way"):
        _ = GroundSurface(1, 0, [0], 0)
    with assert_raises(contains="a ground of 4 columns has 3 layers"):
        _ = GroundSurface(2, 2, [0, 0, 0], 0)
    with assert_raises(contains="a tolerance is 0 layers or more"):
        _ = GroundSurface(1, 1, [0], -1)
    with assert_raises(contains="a ground layer must be -1 to 11"):
        _ = flat_ground(grid, 12)
    with assert_raises(contains="a ground layer must be -1 to 11"):
        _ = flat_ground(grid, -2)
    var other = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(1, METER), 12, 7, 12, 0.5
    )
    with assert_raises(contains="is not the ground of a grid of 12 by 7"):
        flat_ground(grid, 0).check(other)
    var wide = OccupancyGrid(Vec3d(0, 0, 0), Length64(1, METER), 11, 8, 12, 0.5)
    with assert_raises(contains="a ground of 12 by 8 columns"):
        _ = ground_grid(wide, flat_ground(grid, 0))
    var low = List[Int](length=96, fill=0)
    low[95] = -2
    with assert_raises(contains="a ground layer must be -1 to 11"):
        GroundSurface(12, 8, low^, 0).check(grid)
    var high = List[Int](length=96, fill=0)
    high[0] = 12
    with assert_raises(contains="a ground layer must be -1 to 11"):
        GroundSurface(12, 8, high^, 0).check(grid)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
