# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.scan.levels`, the floors and ceilings of
a scan.

The grids are filled by hand, layer by layer, with 0.1 m voxels, so each
floor and ceiling layer is known. A two-storey grid has the unseen inside
of a slab between a ceiling and the floor above it.
"""

from extensions.building.scan.levels import (
    LevelOptions,
    ScanLevels,
    _peaks,
    clear_layers,
    default_level_options,
    detect_levels,
    is_floor_face,
    separation_layers,
)
from extensions.scan.occupancy import OccupancyGrid
from generators.utils import Vec3d
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _grid(columns: Int, nz: Int, layers: List[Int]) raises -> OccupancyGrid:
    """Return a grid of `columns` by `columns` voxel columns, 0.1 m voxels
    from the origin, with every listed layer solid."""
    var grid = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(0.1, METER), columns, columns, nz, 1
    )
    for k in layers:
        for j in range(columns):
            for i in range(columns):
                grid.weights[grid.index(i, j, k)] = 1
    return grid^


def test_the_default_options_are_valid() raises:
    """A quarter of the plan, 2 m between levels and 1 m clear."""
    var options = default_level_options()
    options.check()
    assert_equal(options.min_fraction, 0.25)
    assert_equal(options.min_clear.to(METER), 1)


def test_options_that_find_no_level_are_refused() raises:
    """Each field is checked."""
    var good = default_level_options()
    var options = good
    options.min_fraction = 0
    with assert_raises(contains="the fraction must be above 0 and at most 1"):
        options.check()
    options.min_fraction = 1.5
    with assert_raises(contains="the fraction must be above 0 and at most 1"):
        options.check()
    options = good
    options.min_storey = Length64(0, METER)
    with assert_raises(contains="the storey must be positive"):
        options.check()
    options = good
    options.min_clear = Length64(-1, METER)
    with assert_raises(contains="the clear height must be positive"):
        options.check()
    var grid = _grid(3, 30, [0, 27])
    with assert_raises(contains="the clear height must be positive"):
        _ = detect_levels(grid, options)


def test_the_layer_counts_round_up() raises:
    """Two meters are 20 layers of 0.1 m, and 1.05 m is 11."""
    var grid = _grid(1, 1, List[Int]())
    var options = default_level_options()
    assert_equal(separation_layers(grid, options), 20)
    assert_equal(clear_layers(grid, options), 10)
    options.min_clear = Length64(1.05, METER)
    assert_equal(clear_layers(grid, options), 11)
    options.min_clear = Length64(0.01, METER)
    assert_equal(clear_layers(grid, options), 1)


def test_a_floor_face_needs_clear_height_and_a_ceiling() raises:
    """Empty, covered, open and clear voxels."""
    var grid = _grid(1, 40, [0, 1, 20, 35])
    assert_false(is_floor_face(grid, 0, 0, 5, 10))
    assert_false(is_floor_face(grid, 0, 0, 0, 10))
    assert_false(is_floor_face(grid, 0, 0, 35, 10))
    assert_true(is_floor_face(grid, 0, 0, 1, 10))
    assert_false(is_floor_face(grid, 0, 0, 20, 15))
    assert_true(is_floor_face(grid, 0, 0, 20, 14))
    # With no clear height, a covered voxel's top is a floor face.
    assert_true(is_floor_face(grid, 0, 0, 0, 0))


def test_the_strongest_layers_are_kept_apart() raises:
    """A tie keeps the lower layer; a near layer goes."""
    var counts: List[Int] = [5, 5, 0, 0, 3, 1]
    var kept = _peaks(counts, 2, 2)
    assert_equal(len(kept), 2)
    assert_equal(kept[0], 0)
    assert_equal(kept[1], 4)
    assert_equal(len(_peaks(counts, 9, 2)), 0)


def test_one_room_has_one_floor_and_one_ceiling() raises:
    """The face on top of the ceiling and the face below the floor look at
    nothing."""
    var grid = _grid(3, 30, [0, 27])
    var levels = detect_levels(grid, default_level_options())
    assert_equal(len(levels.floors), 1)
    assert_equal(levels.floors[0], 0)
    assert_equal(len(levels.ceilings), 1)
    assert_equal(levels.ceilings[0], 27)
    assert_equal(levels.top, 27)
    assert_equal(levels.columns, 9)
    assert_false(levels.exterior)
    assert_almost_equal(levels.floor_elevation(grid, 0).to(METER), 0.1)
    assert_almost_equal(levels.ceiling_elevation(grid, 0).to(METER), 2.7)
    assert_almost_equal(levels.top_elevation(grid).to(METER), 2.8)


def test_a_slab_between_storeys_is_not_a_floor() raises:
    """The ceiling's top and the slab's bottom are too close to count."""
    var grid = _grid(3, 60, [0, 27, 30, 57])
    var levels = detect_levels(grid, default_level_options())
    assert_equal(len(levels.floors), 2)
    assert_equal(levels.floors[0], 0)
    assert_equal(levels.floors[1], 30)
    assert_equal(len(levels.ceilings), 2)
    assert_equal(levels.ceilings[0], 27)
    assert_equal(levels.ceilings[1], 57)


def test_a_table_does_not_make_a_floor() raises:
    """One column's table top is too small to count, and hides the floor
    under it."""
    var grid = _grid(3, 30, [0, 27])
    grid.weights[grid.index(1, 1, 8)] = 1
    var levels = detect_levels(grid, default_level_options())
    assert_equal(len(levels.floors), 1)
    assert_equal(levels.floors[0], 0)


def test_an_outside_scan_stands_on_the_ground() raises:
    """With no ceiling over any floor, the lowest broad layer is the
    ground."""
    var grid = _grid(3, 40, [0])
    grid.weights[grid.index(1, 1, 0)] = 0
    for k in range(1, 31):
        grid.weights[grid.index(1, 1, k)] = 1
    var levels = detect_levels(grid, default_level_options())
    assert_true(levels.exterior)
    assert_equal(len(levels.floors), 1)
    assert_equal(levels.floors[0], 0)
    assert_equal(len(levels.ceilings), 0)
    assert_equal(levels.top, 30)


def test_a_scan_needs_a_level() raises:
    """No solid voxel, or no layer broad enough, is refused."""
    with assert_raises(contains="no voxel is solid"):
        _ = detect_levels(_grid(2, 5, List[Int]()), default_level_options())
    var grid = OccupancyGrid(Vec3d(0, 0, 0), Length64(0.1, METER), 2, 2, 40, 1)
    grid.weights[grid.index(0, 0, 0)] = 1
    grid.weights[grid.index(1, 0, 10)] = 1
    grid.weights[grid.index(0, 1, 20)] = 1
    grid.weights[grid.index(1, 1, 30)] = 1
    var options = default_level_options()
    options.min_fraction = 0.5
    with assert_raises(contains="no layer covers enough of the plan"):
        _ = detect_levels(grid, options)


def test_levels_can_be_held_and_copied() raises:
    """The constructor keeps what it is given."""
    var levels = ScanLevels([1, 30], [27], 57, 9, False)
    var copy = levels.copy()
    assert_equal(copy.floors[1], 30)
    assert_equal(copy.ceilings[0], 27)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
