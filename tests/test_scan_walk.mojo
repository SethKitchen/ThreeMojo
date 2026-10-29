# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.walk`, a person walking through a scan.

Rooms are filled by hand in a grid of 0.1 m voxels: a floor, walls, and in
one room a pillar and in another a low slab. The walker must find clear
points, a line between them that it can walk, and then walk it in a physics
world without leaving the room or sinking into the floor.
"""

from extensions.physics.shape import PhysicsMaterial
from extensions.scan.occupancy import OccupancyGrid
from extensions.scan.walk import (
    Walker,
    default_walk_options,
    is_clear,
    is_walkable,
    walk_ends,
)
from generators.utils import Vec3d
from std.math import nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle64,
    Duration,
    KILOGRAM,
    Length64,
    Mass,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Velocity64,
)

comptime NX = 60
comptime NY = 50
comptime NZ = 32
comptime FLOOR = 0.1
"""The floor's top face, in meters: one voxel thick."""


def _room(pillar: Bool, slab: Bool) raises -> OccupancyGrid:
    """Return a room 6 m by 5 m by 3.2 m: a floor, four walls, and with
    `pillar` a column of 0.5 m, and with `slab` a low ceiling over its
    right half."""
    var grid = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(0.1, METER), NX, NY, NZ, 1
    )
    for k in range(NZ):
        for j in range(NY):
            for i in range(NX):
                var wall = i == 0 or j == 0 or i == NX - 1 or j == NY - 1
                var solid = k == 0 or wall
                if (
                    pillar
                    and i >= 28
                    and i < 33
                    and j >= 23
                    and j < 28
                    and k < 28
                ):
                    solid = True
                if slab and i >= NX // 2 and k == 12:
                    solid = True
                if solid:
                    grid.weights[grid.index(i, j, k)] = 1
    return grid^


def test_a_point_is_clear_with_a_floor_and_room_overhead() raises:
    """The middle of an empty room is clear, a wall is not, and a point
    past the floor is not."""
    var grid = _room(False, False)
    var walker = default_walk_options()
    var floor = Length64(FLOOR, METER)
    assert_true(
        is_clear(grid, walker, Length64(3, METER), Length64(2.5, METER), floor)
    )
    assert_true(
        not is_clear(
            grid, walker, Length64(0.2, METER), Length64(2.5, METER), floor
        )
    )
    assert_true(
        not is_clear(
            grid, walker, Length64(-5, METER), Length64(2.5, METER), floor
        )
    )


def test_a_low_slab_or_a_pillar_stops_the_walker() raises:
    """Under a slab at 1.2 m, and at a pillar, no point is clear."""
    var walker = default_walk_options()
    var floor = Length64(FLOOR, METER)
    var slab = _room(False, True)
    assert_true(
        not is_clear(
            slab, walker, Length64(4.5, METER), Length64(2.5, METER), floor
        )
    )
    assert_true(
        is_clear(
            slab, walker, Length64(1.5, METER), Length64(2.5, METER), floor
        )
    )
    var pillar = _room(True, False)
    assert_true(
        not is_clear(
            pillar, walker, Length64(3.0, METER), Length64(2.5, METER), floor
        )
    )
    assert_true(
        is_clear(
            pillar, walker, Length64(1.0, METER), Length64(2.5, METER), floor
        )
    )


def test_a_line_through_a_pillar_cannot_be_walked() raises:
    """A line past the pillar is walkable and a line through it is not."""
    var grid = _room(True, False)
    var walker = default_walk_options()
    var floor = Length64(FLOOR, METER)
    assert_true(
        is_walkable(
            grid,
            walker,
            Length64(1, METER),
            Length64(1, METER),
            Length64(5, METER),
            Length64(1, METER),
            floor,
        )
    )
    assert_true(
        not is_walkable(
            grid,
            walker,
            Length64(1, METER),
            Length64(2.5, METER),
            Length64(5, METER),
            Length64(2.5, METER),
            floor,
        )
    )


def test_the_ends_of_the_walk_are_far_apart_and_in_sight() raises:
    """The two ends are at least three meters apart with a clear line
    between them, in an empty room and in one with a pillar."""
    var walker = default_walk_options()
    var floor = Length64(FLOOR, METER)
    for pillar in [False, True]:
        var grid = _room(pillar, False)
        var ends = walk_ends(
            grid, walker, Vec3d(0, 0, 0), Vec3d(6, 5, 0), floor
        )
        assert_equal(len(ends), 2)
        var dx = ends[1].x - ends[0].x
        var dy = ends[1].y - ends[0].y
        assert_true(sqrt(dx * dx + dy * dy) > 3)
        assert_true(
            is_walkable(
                grid,
                walker,
                Length64(ends[0].x, METER),
                Length64(ends[0].y, METER),
                Length64(ends[1].x, METER),
                Length64(ends[1].y, METER),
                floor,
            )
        )


def test_a_walker_walks_the_room_on_its_floor() raises:
    """Ten seconds of ticks: the walker covers more than six meters, stays
    inside the walls, and stands on the floor throughout."""
    var grid = _room(True, False)
    var walker = Walker(
        grid,
        Length64(FLOOR, METER),
        Vec3d(0, 0, 0),
        Vec3d(6, 5, 0),
        default_walk_options(),
        PhysicsMaterial.default(),
    )
    var start = walker.position()
    var walked = Float64(0)
    var last = start
    assert_almost_equal(walker.eye().z - walker.position().z, 0.75, atol=1e-9)
    assert_almost_equal(
        walker.forward().x ** 2 + walker.forward().y ** 2, 1, atol=1e-9
    )
    for _ in range(600):
        walker.step(Duration(Float32(1.0 / 60), SECOND))
        var here = walker.position()
        walked += sqrt((here.x - last.x) ** 2 + (here.y - last.y) ** 2)
        last = here
        assert_true(here.x > 0.15 and here.x < 5.85)
        assert_true(here.y > 0.15 and here.y < 4.85)
        assert_true(here.z > FLOOR + 0.85 and here.z < FLOOR + 1.05)
    assert_true(walked > 6)


def test_a_walker_behind_its_goal_turns_the_short_way() raises:
    """A walker more than half a turn from its goal turns the other way."""
    var grid = _room(True, False)
    var walker = Walker(
        grid,
        Length64(FLOOR, METER),
        Vec3d(0, 0, 0),
        Vec3d(6, 5, 0),
        default_walk_options(),
        PhysicsMaterial.default(),
    )
    var facing = walker.yaw
    walker.yaw = facing - 4.0
    walker.step(Duration(Float32(1.0 / 60), SECOND))
    assert_true(walker.yaw < facing - 4.0)
    walker.yaw = facing + 4.0
    walker.step(Duration(Float32(1.0 / 60), SECOND))
    assert_true(walker.yaw > facing + 4.0)


def test_a_room_with_no_clear_floor_has_no_walk() raises:
    """A solid block has no point to stand on."""
    var grid = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(0.1, METER), 20, 20, 20, 1
    )
    for at in range(len(grid.weights)):
        grid.weights[at] = 1
    with assert_raises(contains="no clear floor to walk on"):
        _ = walk_ends(
            grid,
            default_walk_options(),
            Vec3d(0, 0, 0),
            Vec3d(2, 2, 0),
            Length64(0.1, METER),
        )


def test_a_walker_must_fit_in_the_world() raises:
    """Each number of the options is checked."""
    var good = default_walk_options()
    good.check()
    var bad = good
    bad.radius = Length64(0, METER)
    with assert_raises(contains="the radius must be positive"):
        bad.check()
    bad = good
    bad.height = Length64(nan[DType.float64](), METER)
    with assert_raises(contains="the height must be positive"):
        bad.check()
    bad = good
    bad.speed = Velocity64(-1, METER_PER_SECOND)
    with assert_raises(contains="the speed must be positive"):
        bad.check()
    bad = good
    bad.turn = Angle64(0, RADIAN)
    with assert_raises(contains="the turn must be positive"):
        bad.check()
    bad = good
    bad.step = Length64(0, METER)
    with assert_raises(contains="the step must be positive"):
        bad.check()
    bad = good
    bad.spacing = Length64(0, METER)
    with assert_raises(contains="the spacing must be positive"):
        bad.check()
    bad = good
    bad.eye = Length64(nan[DType.float64](), METER)
    with assert_raises(contains="the eye must be finite"):
        bad.check()
    bad = good
    bad.mass = Mass(0, KILOGRAM)
    with assert_raises(contains="the mass must be positive"):
        bad.check()
    bad = good
    bad.height = Length64(0.5, METER)
    with assert_raises(contains="at least twice the radius"):
        bad.check()
    bad = good
    bad.eye = Length64(1.2, METER)
    with assert_raises(contains="the eye must be inside the capsule"):
        bad.check()
    bad = good
    bad.clearance = Length64(0.2, METER)
    with assert_raises(contains="the clearance must be above the step"):
        bad.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
