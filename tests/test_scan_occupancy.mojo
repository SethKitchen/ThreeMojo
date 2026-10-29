# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.occupancy`, the occupancy grid of a scan.

The room of `tests/_scan_room.mojo` is 4 m by 5 m, with its floor at 0 m
and its ceiling at 2.7 m. In a region that starts half a voxel below each
surface, each surface falls in the middle of one layer of voxels, so the
solid voxels are known exactly.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from extensions.scan.frame import supersplat_frame
from extensions.scan.occupancy import (
    OccupancyGrid,
    ScanRegion,
    _trimmed,
    default_occupancy_options,
    occupancy_grid,
    trimmed_region,
)
from generators.utils import Vec3d
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._scan_room import default_room, room_scan
from units.si import Length64, METER


def _room_region() -> ScanRegion:
    """Return the room's box, half a voxel past each surface."""
    return ScanRegion(Vec3d(-0.05, -0.05, -0.05), Vec3d(4.05, 5.05, 2.75))


def test_the_default_options_are_valid() raises:
    """The defaults pass their own check."""
    var options = default_occupancy_options()
    options.check()
    assert_equal(options.voxel.to(METER), 0.1)
    assert_equal(options.reach, 2)


def test_options_that_cannot_make_a_grid_are_refused() raises:
    """Each field is checked."""
    var good = default_occupancy_options()
    var options = good
    options.voxel = Length64(0, METER)
    with assert_raises(contains="the voxel must be positive"):
        options.check()
    options = good
    options.min_opacity = 1.5
    with assert_raises(contains="the least opacity must be 0 to 1"):
        options.check()
    options = good
    options.solid_weight = 0
    with assert_raises(contains="the solid weight must be positive"):
        options.check()
    options = good
    options.reach = -1
    with assert_raises(contains="the reach cannot be negative"):
        options.check()
    options = good
    options.trim = -0.1
    with assert_raises(contains="the trim must be 0 to under one half"):
        options.check()
    options.trim = 0.5
    with assert_raises(contains="the trim must be 0 to under one half"):
        options.check()
    options = good
    options.max_voxels = 0
    with assert_raises(contains="the voxel limit must be positive"):
        options.check()


def test_a_region_must_be_a_finite_box() raises:
    """A corner that is not finite, or a box flat on any axis, is refused."""
    _room_region().check()
    with assert_raises(contains="a region corner must be finite"):
        ScanRegion(Vec3d(0, 0, 0), Vec3d(1, inf[DType.float64](), 1)).check()
    var flat: List[Vec3d] = [Vec3d(0, 1, 1), Vec3d(1, 0, 1), Vec3d(1, 1, 0)]
    for high in flat:
        with assert_raises(contains="a region must be above its low corner"):
            ScanRegion(Vec3d(0, 0, 0), high).check()


def test_a_grid_has_voxels_each_way() raises:
    """A count below one, or an edge or weight that is not positive, is
    refused."""
    var origin = Vec3d(0, 0, 0)
    var edge = Length64(1, METER)
    with assert_raises(contains="at least one voxel each way"):
        _ = OccupancyGrid(origin, edge, 0, 1, 1, 1)
    with assert_raises(contains="at least one voxel each way"):
        _ = OccupancyGrid(origin, edge, 1, 0, 1, 1)
    with assert_raises(contains="at least one voxel each way"):
        _ = OccupancyGrid(origin, edge, 1, 1, 0, 1)
    with assert_raises(contains="the voxel must be positive"):
        _ = OccupancyGrid(origin, Length64(0, METER), 1, 1, 1, 1)
    with assert_raises(contains="the solid weight must be positive"):
        _ = OccupancyGrid(origin, edge, 1, 1, 1, 0)


def test_a_grid_knows_its_voxels() raises:
    """Indexes run x fastest; a voxel outside the grid is empty."""
    var grid = OccupancyGrid(Vec3d(1, 2, 3), Length64(0.5, METER), 2, 3, 4, 1)
    assert_equal(grid.index(1, 2, 3), (3 * 3 + 2) * 2 + 1)
    assert_true(grid.contains(0, 0, 0))
    var outside: List[Int] = [
        -1,
        0,
        0,
        2,
        0,
        0,
        0,
        -1,
        0,
        0,
        3,
        0,
        0,
        0,
        -1,
        0,
        0,
        4,
    ]
    for item in range(6):
        assert_false(
            grid.contains(
                outside[item * 3], outside[item * 3 + 1], outside[item * 3 + 2]
            )
        )
    assert_false(grid.is_solid(5, 0, 0))
    grid.weights[grid.index(1, 1, 1)] = 0.75
    assert_false(grid.is_solid(1, 1, 1))
    grid.weights[grid.index(1, 1, 1)] = 1
    assert_true(grid.is_solid(1, 1, 1))
    assert_equal(grid.solid_count(), 1)
    var corner = grid.corner(1, 2, 3)
    assert_equal(corner.x, 1.5)
    assert_equal(corner.y, 3)
    assert_equal(corner.z, 4.5)
    assert_equal(grid.top(), 5)


def test_the_trimmed_range_leaves_out_each_end() raises:
    """With a tenth trimmed, the lowest and highest of ten values go."""
    var values: List[Float64] = [9, 0, 8, 1, 7, 2, 6, 3, 5, 4]
    var kept = _trimmed(values, 0.1)
    assert_equal(kept[0], 1)
    assert_equal(kept[1], 8)
    var all = _trimmed(values, 0)
    assert_equal(all[0], 0)
    assert_equal(all[1], 9)


def test_the_region_of_the_room_is_one_voxel_past_it() raises:
    """The walls hold far more splats than the trim, so the range is the
    room's own, one voxel larger on each side."""
    var region = trimmed_region(
        room_scan(default_room()),
        supersplat_frame(),
        default_occupancy_options(),
    )
    assert_almost_equal(region.low.x, -0.1, atol=1e-6)
    assert_almost_equal(region.low.y, -0.1, atol=1e-6)
    assert_almost_equal(region.low.z, -0.1, atol=1e-6)
    assert_almost_equal(region.high.x, 4.1, atol=1e-6)
    assert_almost_equal(region.high.y, 5.1, atol=1e-6)
    assert_almost_equal(region.high.z, 2.8, atol=1e-6)


def test_a_region_needs_opaque_splats() raises:
    """Splats below the least opacity leave nothing to bound."""
    var options = default_occupancy_options()
    options.min_opacity = 0.95
    with assert_raises(contains="no splat is opaque enough"):
        _ = trimmed_region(
            room_scan(default_room()), supersplat_frame(), options
        )
    with assert_raises(contains="no splat is opaque enough"):
        _ = trimmed_region(
            GaussianSplatGeometry(),
            supersplat_frame(),
            default_occupancy_options(),
        )
    var bad = supersplat_frame()
    bad.unit = Length64(0, METER)
    with assert_raises(contains="the unit must be positive"):
        _ = trimmed_region(room_scan(default_room()), bad, options)
    options.reach = -3
    with assert_raises(contains="the reach cannot be negative"):
        _ = trimmed_region(
            room_scan(default_room()), supersplat_frame(), options
        )


def test_the_room_fills_its_surfaces_and_not_its_air() raises:
    """The floor, the ceiling and the four walls are solid layers; the
    middle of the room is empty."""
    var grid = occupancy_grid(
        room_scan(default_room()),
        supersplat_frame(),
        default_occupancy_options(),
        _room_region(),
    )
    assert_equal(grid.nx, 41)
    assert_equal(grid.ny, 51)
    assert_equal(grid.nz, 28)
    for i in range(41):
        for j in range(51):
            assert_true(grid.is_solid(i, j, 0))
            assert_true(grid.is_solid(i, j, 27))
            for k in range(1, 27):
                var wall = i == 0 or i == 40 or j == 0 or j == 50
                assert_equal(grid.is_solid(i, j, k), wall)


def test_splats_outside_the_region_add_nothing() raises:
    """Half the room's plan holds half its floor."""
    var grid = occupancy_grid(
        room_scan(default_room()),
        supersplat_frame(),
        default_occupancy_options(),
        ScanRegion(Vec3d(-0.05, -0.05, -0.05), Vec3d(2.05, 5.05, 2.75)),
    )
    assert_equal(grid.nx, 21)
    assert_true(grid.is_solid(20, 25, 0))


def test_faint_splats_and_a_wide_reach_follow_the_options() raises:
    """No splat counts above its opacity; a reach of zero keeps each
    splat in its own voxel, so a coarse scan leaves gaps."""
    var options = default_occupancy_options()
    options.min_opacity = 0.95
    var empty = occupancy_grid(
        room_scan(default_room()), supersplat_frame(), options, _room_region()
    )
    assert_equal(empty.solid_count(), 0)
    options = default_occupancy_options()
    options.reach = 0
    var sparse = occupancy_grid(
        room_scan(default_room()), supersplat_frame(), options, _room_region()
    )
    # Splats are 0.2 m apart and voxels 0.1 m, so a quarter of the floor
    # voxels hold a splat.
    var floor = 0
    for i in range(41):
        for j in range(51):
            if sparse.is_solid(i, j, 0):
                floor += 1
    assert_equal(floor, 21 * 26)


def test_a_region_too_large_for_the_limit_is_refused() raises:
    """The limit is checked in floats, so a vast region cannot overflow."""
    var options = default_occupancy_options()
    options.max_voxels = 1000
    var room = room_scan(default_room())
    with assert_raises(contains="needs more than 1000 voxels"):
        _ = occupancy_grid(room, supersplat_frame(), options, _room_region())
    with assert_raises(contains="voxels; use a larger voxel"):
        _ = occupancy_grid(
            room,
            supersplat_frame(),
            default_occupancy_options(),
            ScanRegion(Vec3d(0, 0, 0), Vec3d(1e300, 1e300, 1e300)),
        )
    with assert_raises(contains="a region corner must be finite"):
        _ = occupancy_grid(
            room,
            supersplat_frame(),
            default_occupancy_options(),
            ScanRegion(Vec3d(nan[DType.float64](), 0, 0), Vec3d(1, 1, 1)),
        )
    var bad = default_occupancy_options()
    bad.max_voxels = -1
    with assert_raises(contains="the voxel limit must be positive"):
        _ = occupancy_grid(room, supersplat_frame(), bad, _room_region())
    var frame = supersplat_frame()
    frame.unit = Length64(-2, METER)
    with assert_raises(contains="the unit must be positive"):
        _ = occupancy_grid(
            room, frame, default_occupancy_options(), _room_region()
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
