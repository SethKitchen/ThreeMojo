# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.scan.fit`, a building model fitted to a
scan.

The rooms and the house of `tests/_scan_room.mojo` are known exactly. In
a region that starts half a voxel below each surface, a wall's voxels
span 5 cm on each side of it, so a fitted room's plan is the room less
5 cm on each side, and its storey ends at the face below its ceiling.
"""

from extensions.building.ids import ConstructionId
from extensions.building.kinds import LIVING, SpaceUse
from extensions.building.kits import (
    KitKind,
    MASONRY_KIT,
    STONE_KIT,
    construction_kit,
)
from extensions.building.model import Site
from extensions.building.scan.fit import (
    ScanFitOptions,
    _trimmed_index,
    fit_building,
)
from extensions.building.scan.levels import (
    ScanLevels,
    default_level_options,
    detect_levels,
)
from extensions.scan.frame import (
    SCALE_ASSUMED,
    SCALE_DECLARED,
    SCALE_MEASURED,
    ScaleSource,
    supersplat_frame,
)
from extensions.scan.occupancy import (
    OccupancyGrid,
    ScanRegion,
    default_occupancy_options,
    occupancy_grid,
)
from generators.utils import Vec3d
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._scan_room import default_room, house_scan, room_scan
from units.si import Angle64, DEGREE64, Length64, METER, SQUARE_METER


def _site() -> Site:
    """Return a site in Warsaw."""
    return Site(
        Angle64(52.2, DEGREE64),
        Angle64(21.0, DEGREE64),
        Length64(100, METER),
        Angle64(0, DEGREE64),
    )


def _options() -> ScanFitOptions:
    """Return fit options for a dwelling."""
    return ScanFitOptions(
        "scan", _site(), LIVING, 0.01, default_level_options()
    )


def _room_grid(storeys: Int) raises -> OccupancyGrid:
    """Return the grid of a room of one or more storeys."""
    var plan = default_room()
    plan.storeys = storeys
    var top = Float64(storeys) * plan.storey - plan.slab + 0.05
    return occupancy_grid(
        room_scan(plan),
        supersplat_frame(),
        default_occupancy_options(),
        ScanRegion(Vec3d(-0.05, -0.05, -0.05), Vec3d(4.05, 5.05, top)),
    )


def test_the_trimmed_index_range_leaves_out_each_end() raises:
    """With a fifth trimmed, the lowest and highest of five go."""
    var kept = _trimmed_index([4, 0, 3, 1, 2], 0.2)
    assert_equal(kept[0], 1)
    assert_equal(kept[1], 3)


def test_options_that_cannot_fit_are_refused() raises:
    """The site, the use, the trim and the level options are checked."""
    var options = _options()
    options.site.latitude = Angle64(120, DEGREE64)
    with assert_raises():
        options.check()
    options = _options()
    options.use = SpaceUse(40)
    with assert_raises(contains="a space use is not valid"):
        options.check()
    options = _options()
    options.trim = 0.5
    with assert_raises(contains="the trim must be 0 to under one half"):
        options.check()
    options.trim = -0.5
    with assert_raises(contains="the trim must be 0 to under one half"):
        options.check()
    options = _options()
    options.levels.min_fraction = 2
    with assert_raises(contains="the fraction must be above 0"):
        options.check()


def test_one_room_becomes_one_storey_inside_its_walls() raises:
    """The plan is 3.9 m by 4.9 m and the storey 2.6 m: floor face 0.05 m,
    ceiling face 2.65 m."""
    var grid = _room_grid(1)
    var levels = detect_levels(grid, default_level_options())
    var fit = fit_building(
        grid, levels, construction_kit(MASONRY_KIT), SCALE_DECLARED, _options()
    )
    fit.building.validate()
    assert_equal(len(fit.building.storeys), 1)
    assert_almost_equal(
        fit.building.storeys[0].height.to(METER), 2.6, atol=1e-9
    )
    assert_almost_equal(
        fit.building.storeys[0].elevation.to(METER), 0.05, atol=1e-9
    )
    assert_almost_equal(
        fit.building.gross_floor_area().to(SQUARE_METER), 3.9 * 4.9, atol=1e-6
    )
    assert_equal(len(fit.fill), 1)
    assert_almost_equal(fit.fill[0], 1)
    assert_true(fit.scale == SCALE_DECLARED)
    assert_false(fit.levels.exterior)
    assert_equal(len(fit.notes), 3)
    assert_true("100 percent" in fit.notes[0])
    assert_true("declared, not measured" in fit.notes[1])
    assert_true("masonry kit" in fit.notes[2])


def test_two_storeys_stack_floor_to_floor() raises:
    """Storey 0 runs floor to floor, 3 m; storey 1 to its ceiling, 2.6 m;
    and the ceiling below storey 1's floor is passed over."""
    var grid = _room_grid(2)
    var levels = detect_levels(grid, default_level_options())
    var fit = fit_building(
        grid, levels, construction_kit(STONE_KIT), SCALE_MEASURED, _options()
    )
    assert_equal(len(fit.building.storeys), 2)
    assert_almost_equal(
        fit.building.storeys[0].height.to(METER), 3.0, atol=1e-9
    )
    assert_almost_equal(
        fit.building.storeys[1].height.to(METER), 2.6, atol=1e-9
    )
    # A measured scale adds no warning: two storey notes and the kit's.
    assert_equal(len(fit.notes), 3)
    assert_true("stone kit" in fit.notes[2])


def test_an_outside_scan_is_one_storey_to_the_top() raises:
    """The house is 4 m by 5 m and 3 m high, and its ground is 1 m wide
    around it. The roof splats reach one voxel past each wall, so the plan
    is 4.3 m by 5.3 m."""
    var plan = default_room()
    var grid = occupancy_grid(
        house_scan(plan, 1),
        supersplat_frame(),
        default_occupancy_options(),
        ScanRegion(Vec3d(-1.05, -1.05, -0.05), Vec3d(5.05, 6.05, 3.05)),
    )
    var levels = detect_levels(grid, default_level_options())
    assert_true(levels.exterior)
    var fit = fit_building(
        grid, levels, construction_kit(MASONRY_KIT), SCALE_ASSUMED, _options()
    )
    assert_equal(len(fit.building.storeys), 1)
    assert_almost_equal(
        fit.building.storeys[0].height.to(METER), 3.0, atol=1e-9
    )
    assert_almost_equal(
        fit.building.gross_floor_area().to(SQUARE_METER), 4.3 * 5.3, atol=1e-6
    )
    assert_true("outside view" in fit.notes[1])
    assert_true("assumed length" in fit.notes[2])


def test_a_fit_needs_a_valid_kit_scale_and_storeys() raises:
    """Each input is checked before the model is built."""
    var grid = _room_grid(1)
    var levels = detect_levels(grid, default_level_options())
    var kit = construction_kit(MASONRY_KIT)
    kit.kind = KitKind(7)
    with assert_raises(contains="a kit kind is 0 to 3"):
        _ = fit_building(grid, levels, kit, SCALE_DECLARED, _options())
    with assert_raises(contains="a scale source is 0 to 2"):
        _ = fit_building(
            grid,
            levels,
            construction_kit(MASONRY_KIT),
            ScaleSource(4),
            _options(),
        )
    var bad = _options()
    bad.trim = 0.9
    with assert_raises(contains="the trim must be"):
        _ = fit_building(
            grid, levels, construction_kit(MASONRY_KIT), SCALE_DECLARED, bad
        )
    var none = ScanLevels(List[Int](), List[Int](), 27, 2091, False)
    with assert_raises(contains="the levels have no floor"):
        _ = fit_building(
            grid,
            none,
            construction_kit(MASONRY_KIT),
            SCALE_DECLARED,
            _options(),
        )
    var empty = ScanLevels([5], List[Int](), 27, 2091, False)
    with assert_raises(contains="a storey has no floor to fit"):
        _ = fit_building(
            grid,
            empty,
            construction_kit(MASONRY_KIT),
            SCALE_DECLARED,
            _options(),
        )
    var flat = ScanLevels([0], List[Int](), 0, 2091, False)
    with assert_raises(contains="storey 0 has no height"):
        _ = fit_building(
            grid,
            flat,
            construction_kit(MASONRY_KIT),
            SCALE_DECLARED,
            _options(),
        )


def _hand_grid(columns: Int, nz: Int) raises -> OccupancyGrid:
    """Return an empty grid of 0.1 m voxels, `columns` square in plan."""
    return OccupancyGrid(
        Vec3d(0, 0, 0), Length64(0.1, METER), columns, columns, nz, 1
    )


def test_a_hidden_floor_column_lowers_the_fill() raises:
    """With one of 16 floor columns unseen, the rectangle is still the
    whole plan, and the scan saw 15/16 of it."""
    var grid = _hand_grid(4, 30)
    for j in range(4):
        for i in range(4):
            grid.weights[grid.index(i, j, 27)] = 1
            if i != 3 or j != 3:
                grid.weights[grid.index(i, j, 0)] = 1
    var options = _options()
    options.trim = 0
    var fit = fit_building(
        grid,
        detect_levels(grid, default_level_options()),
        construction_kit(MASONRY_KIT),
        SCALE_MEASURED,
        options,
    )
    assert_almost_equal(fit.fill[0], 15.0 / 16)
    assert_almost_equal(
        fit.building.gross_floor_area().to(SQUARE_METER), 0.16, atol=1e-9
    )


def test_an_outside_scan_too_low_for_its_plan_is_refused() raises:
    """The plan of an outside scan starts a meter above the ground; a grid
    that ends below it has no plan."""
    var grid = _hand_grid(3, 11)
    for j in range(3):
        for i in range(3):
            grid.weights[grid.index(i, j, 0)] = 1
    for k in range(1, 11):
        grid.weights[grid.index(1, 1, k)] = 1
    grid.weights[grid.index(1, 1, 0)] = 0
    var levels = detect_levels(grid, default_level_options())
    assert_true(levels.exterior)
    with assert_raises(contains="a storey has no floor to fit"):
        _ = fit_building(
            grid,
            levels,
            construction_kit(MASONRY_KIT),
            SCALE_MEASURED,
            _options(),
        )


def test_a_fit_reads_on_into_every_view() raises:
    """The fitted model writes as IFC, so the views read it as any model."""
    from extensions.building.ifc.ifc4 import write_ifc

    var grid = _room_grid(1)
    var fit = fit_building(
        grid,
        detect_levels(grid, default_level_options()),
        construction_kit(MASONRY_KIT),
        SCALE_DECLARED,
        _options(),
    )
    var text = write_ifc(fit.building, "2026-10-20T00:00:00")
    assert_true("IFCWALL" in text)
    assert_true("IFCSLAB" in text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
