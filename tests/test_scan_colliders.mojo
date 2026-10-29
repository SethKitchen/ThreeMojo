# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.colliders`, the static collider of a scan.

Small grids are filled by hand, so the merged rectangles can be counted.
Each triangle's front must face away from the solid voxel it bounds. A
sphere dropped in the scanned room of `tests/_scan_room.mojo` must come to
rest on the top face of the floor's voxels.
"""

from extensions.physics.body import DYNAMIC, RigidBody
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from extensions.scan.colliders import (
    _cell,
    _point,
    add_scan_collider,
    collision_triangles,
    scan_collider,
)
from extensions.scan.frame import supersplat_frame
from extensions.scan.occupancy import (
    OccupancyGrid,
    ScanRegion,
    default_occupancy_options,
    occupancy_grid,
)
from generators.utils import Vec3d
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.cross import cross_vectors
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._scan_room import default_room, room_scan
from units.si import Duration, KILOGRAM, Length, Length64, Mass, METER, SECOND


def _grid(nx: Int, ny: Int, nz: Int, solid: List[Int]) raises -> OccupancyGrid:
    """Return a grid of 1 m voxels at the origin with the listed voxels
    solid, three indexes each."""
    var grid = OccupancyGrid(Vec3d(0, 0, 0), Length64(1, METER), nx, ny, nz, 1)
    for at in range(len(solid) // 3):
        grid.weights[
            grid.index(solid[at * 3], solid[at * 3 + 1], solid[at * 3 + 2])
        ] = 1
    return grid^


def _outward(triangles: List[Triangle], inside: Vector3) raises:
    """Assert every triangle's front faces away from a point inside."""
    for triangle in triangles:
        var normal = cross_vectors(
            triangle.b - triangle.a, triangle.c - triangle.a
        )
        var middle = (triangle.a + triangle.b + triangle.c) * Float32(1.0 / 3)
        assert_true(normal.dot(middle - inside) > 0)


def test_the_corners_and_cells_follow_the_axis() raises:
    """Each axis places its slice index and its in-plane indexes."""
    var a = _point(0, 1, 2, 3)
    assert_equal(a.x, 1)
    assert_equal(a.y, 2)
    assert_equal(a.z, 3)
    var b = _point(1, 1, 2, 3)
    assert_equal(b.x, 3)
    assert_equal(b.y, 1)
    assert_equal(b.z, 2)
    var c = _point(2, 1, 2, 3)
    assert_equal(c.x, 2)
    assert_equal(c.y, 3)
    assert_equal(c.z, 1)
    var i: Int
    var j: Int
    var k: Int
    i, j, k = _cell(1, 7, 8, 9)
    assert_equal(i, 9)
    assert_equal(j, 7)
    assert_equal(k, 8)


def test_one_voxel_is_a_cube_of_twelve_triangles() raises:
    """Six faces, none merged, each facing out."""
    var triangles = collision_triangles(_grid(1, 1, 1, [0, 0, 0]))
    assert_equal(len(triangles), 12)
    _outward(triangles, Vector3(0.5, 0.5, 0.5))
    var area = Float32(0)
    for triangle in triangles:
        area += triangle.area()
    assert_almost_equal(area, 6, atol=1e-5)


def test_a_slab_merges_into_one_rectangle_a_side() raises:
    """A 3 by 3 by 1 slab inside a larger grid has six rectangles."""
    var solid = List[Int]()
    for i in range(3):
        for j in range(3):
            solid.extend([i + 1, j + 1, 1])
    var triangles = collision_triangles(_grid(5, 5, 3, solid))
    assert_equal(len(triangles), 12)
    _outward(triangles, Vector3(2.5, 2.5, 1.5))


def test_an_l_shape_stops_each_run_and_each_rise() raises:
    """An L of three voxels: the top is two rectangles, as each run and
    each rise stops at an empty voxel or at the grid's edge."""
    var triangles = collision_triangles(
        _grid(2, 2, 1, [0, 0, 0, 1, 0, 0, 0, 1, 0])
    )
    var up = 0
    for triangle in triangles:
        var normal = cross_vectors(
            triangle.b - triangle.a, triangle.c - triangle.a
        )
        if normal.z > 0:
            up += 1
    assert_equal(up, 4)


def test_an_empty_grid_has_no_collider() raises:
    """No solid voxel gives no triangle, and no body."""
    var grid = _grid(2, 2, 2, List[Int]())
    assert_equal(len(collision_triangles(grid)), 0)
    with assert_raises(contains="no voxel is solid"):
        _ = scan_collider(grid, PhysicsMaterial.default())


def test_the_collider_keeps_its_material() raises:
    """The surfaces take the material; one that is not valid is refused."""
    var grid = _grid(1, 1, 1, [0, 0, 0])
    var body = scan_collider(grid, PhysicsMaterial(0.9, 0.1))
    assert_almost_equal(body.material.friction, 0.9)
    with assert_raises():
        _ = scan_collider(grid, PhysicsMaterial(-1, 0))


def test_a_ball_rests_on_the_scanned_floor() raises:
    """The floor voxels end 0.05 m above the floor splats, so a 0.25 m ball
    rests with its center 0.30 m up."""
    var grid = occupancy_grid(
        room_scan(default_room()),
        supersplat_frame(),
        default_occupancy_options(),
        ScanRegion(Vec3d(-0.05, -0.05, -0.05), Vec3d(4.05, 5.05, 2.75)),
    )
    var world = PhysicsWorld()
    _ = add_scan_collider(world, grid, PhysicsMaterial.default())
    var ball = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.25)),
        Mass(5, KILOGRAM),
        Vector3(2, 2.5, 1.5),
        Quaternion.identity(),
    )
    var id = world.add_body(ball^)
    for _ in range(120):
        world.step(Duration(1.0 / 60, SECOND))
    var position = world.bodies[id.value].position
    assert_almost_equal(position.z, 0.30, atol=0.02)
    assert_almost_equal(position.x, 2, atol=0.01)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
