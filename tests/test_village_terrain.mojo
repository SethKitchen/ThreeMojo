# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's terrain: wall spans that push a character out, floors
that carry it, ceilings over them, and the camera's sight past walls."""

from extensions.vegetation.ground import Ground, Lot
from extensions.village.terrain import (
    OPEN_SKY,
    Floor,
    Terrain,
    WallSpan,
    view_entry,
    wall_push,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import METER, Length


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _wall() -> WallSpan:
    """Return a wall along x from 0 to 4, 0.2 meters thick, from the
    ground to 3 meters."""
    return WallSpan(0, 0, 4, 0, 0.1, 0, 3)


def test_a_span_finds_its_nearest_point_and_its_height() raises:
    var wall = _wall()
    var near = wall.nearest(2, 5)
    assert_almost_equal(near.x, 2, atol=1e-6)
    assert_almost_equal(near.z, 0, atol=1e-6)
    # Past an end, the end is nearest.
    assert_almost_equal(wall.nearest(-3, 1).x, 0, atol=1e-6)
    assert_almost_equal(wall.nearest(9, -1).x, 4, atol=1e-6)
    # A span whose ends are one point is that point.
    var post = WallSpan(1, 2, 1, 2, 0.1, 0, 3)
    assert_almost_equal(post.nearest(5, 5).z, 2, atol=1e-6)
    # Its foot must be under the head, and its top over the feet.
    assert_true(wall.blocks(0, 1.5))
    assert_false(wall.blocks(3.5, 5))
    var lintel = WallSpan(0, 0, 4, 0, 0.1, 2.1, 3)
    assert_false(lintel.blocks(0, 1.5))


def test_a_wall_pushes_a_circle_straight_out() raises:
    var wall = _wall()
    var clear = wall_push(wall, 2, 1, 0.3)
    assert_almost_equal(clear.z, 1, atol=1e-6)
    var near = wall_push(wall, 2, 0.2, 0.3)
    assert_almost_equal(near.x, 2, atol=1e-6)
    assert_almost_equal(near.z, 0.4, atol=1e-5)
    var below = wall_push(wall, 2, -0.2, 0.3)
    assert_almost_equal(below.z, -0.4, atol=1e-5)
    # Round the end, it pushes away from the end.
    var end = wall_push(wall, 4.2, 0.1, 0.3)
    var gap = (end - Vector3(4, 0, 0)).length()
    assert_almost_equal(gap, 0.4, atol=1e-5)
    # Right on the middle line it goes to the line's left, seen from its
    # first end: +z for a wall along +x.
    var middle = wall_push(wall, 1, 0, 0.3)
    assert_almost_equal(middle.z, 0.4, atol=1e-5)
    # A post with no length pushes toward +x.
    var post = WallSpan(1, 2, 1, 2, 0.1, 0, 3)
    var pushed = wall_push(post, 1, 2, 0.3)
    assert_almost_equal(pushed.x, 1.4, atol=1e-5)
    assert_almost_equal(pushed.z, 2, atol=1e-6)


def test_a_way_enters_a_wall_where_it_crosses_it() raises:
    var wall = _wall()
    # Straight through the middle of the wall, at mid height.
    var t = view_entry(wall, Vector3(2, 1.5, 2), Vector3(2, 1.5, -2))
    assert_almost_equal(t, 0.475, atol=1e-5)
    # A way over the wall's top never enters it.
    assert_equal(view_entry(wall, Vector3(2, 4, 2), Vector3(2, 4, -2)), 1)
    # A way past the wall's end never enters it.
    assert_equal(view_entry(wall, Vector3(6, 1, 2), Vector3(6, 1, -2)), 1)
    # A way along the wall, beside it, never enters it; one inside its
    # thickness does, at its start.
    assert_equal(view_entry(wall, Vector3(-1, 1, 1), Vector3(5, 1, 1)), 1)
    assert_almost_equal(
        view_entry(wall, Vector3(-1, 1, 0), Vector3(5, 1, 0)),
        Float32(1) / 6,
        atol=1e-5,
    )
    # A level way below the wall's foot never enters it.
    assert_equal(view_entry(wall, Vector3(2, -1, 2), Vector3(2, -1, -2)), 1)
    # A span with no length is never entered.
    var post = WallSpan(1, 2, 1, 2, 0.1, 0, 3)
    assert_equal(view_entry(post, Vector3(1, 1, 3), Vector3(1, 1, 1)), 1)


def test_floors_carry_and_ceilings_cover() raises:
    var ground = _flat()
    var floors: List[Floor] = [
        Floor(Lot(0, 0, 2, 2, 0), 0.5, 3.0),
        Floor(Lot(1, 0, 1, 1, 0), 0.8, 3.2),
        Floor(Lot(-1.5, 0, 1, 1, 0), 0.2, OPEN_SKY),
    ]
    var terrain = Terrain(ground, List[Lot](), List[WallSpan](), floors^)
    # Off the floors, the ground.
    assert_equal(terrain.floor_under(10, 10), -1)
    assert_almost_equal(terrain.height_at(10, 10), ground.height_at(10, 10))
    assert_equal(terrain.ceiling_over(10, 10), OPEN_SKY)
    # On one floor, its height and its ceiling.
    assert_equal(terrain.floor_under(0, 1.5), 0)
    assert_almost_equal(terrain.height_at(0, 1.5), 0.5)
    assert_almost_equal(terrain.ceiling_over(0, 1.5), 3)
    # Where two overlap, the higher carries.
    assert_equal(terrain.floor_under(1.5, 0), 1)
    assert_almost_equal(terrain.height_at(1.5, 0), 0.8)
    # The lower of two that overlap is passed over.
    assert_equal(terrain.floor_under(-1.5, 0), 0)


def test_bare_ground_is_a_terrain() raises:
    var ground = _flat()
    var terrain: Terrain = ground
    assert_equal(len(terrain.walls), 0)
    assert_equal(len(terrain.floors), 0)
    assert_equal(len(terrain.lots), 0)
    assert_equal(terrain.view_reach(Vector3(0, 1, 0), Vector3(0, 1, 4), 0.3), 1)


def test_a_camera_stands_before_the_walls() raises:
    var walls: List[WallSpan] = [_wall(), WallSpan(0, -2, 4, -2, 0.1, 0, 3)]
    var terrain = Terrain(_flat(), List[Lot](), walls^, List[Floor]())
    # The nearer wall stops the eye, a margin before it.
    var reach = terrain.view_reach(Vector3(2, 1.5, 2), Vector3(2, 1.5, -2), 0.3)
    assert_almost_equal(reach, 0.4, atol=1e-5)
    # A way clear of both is whole.
    assert_equal(
        terrain.view_reach(Vector3(2, 1.5, 2), Vector3(2, 1.5, 4), 0.3), 1
    )
    # A wall right at the focus leaves no room.
    assert_equal(
        terrain.view_reach(Vector3(2, 1.5, 0.05), Vector3(2, 1.5, -2), 0.3),
        0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
