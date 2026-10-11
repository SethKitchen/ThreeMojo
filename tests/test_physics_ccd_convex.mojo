# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Boxes and hulls that only translate, swept exactly under CCD.

Each case has a hand-computed time of impact and normal.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD, _sweep_convex_triangle
from extensions.physics.shape import PhysicsMaterial, Polyhedron, Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_true,
    assert_equal,
    assert_almost_equal,
    assert_raises,
)
from units.si import Length, Mass, Duration


def _v(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def _cube(
    center: SIMD[DType.float64, 4],
) -> Tuple[
    List[SIMD[DType.float64, 4]],
    List[SIMD[DType.float64, 4]],
    List[SIMD[DType.float64, 4]],
]:
    # A cube of half size 0.5: its corners, face normals and edges.
    var box = Polyhedron.box(Vector3(0.5, 0.5, 0.5))
    var corners = List[SIMD[DType.float64, 4]]()
    for corner in box.vertices:
        corners.append(
            SIMD[DType.float64, 4](
                Float64(corner.x), Float64(corner.y), Float64(corner.z), 0
            )
            + center
        )
    var faces = List[SIMD[DType.float64, 4]]()
    for normal in box.normals:
        faces.append(
            SIMD[DType.float64, 4](
                Float64(normal.x), Float64(normal.y), Float64(normal.z), 0
            )
        )
    var edges = List[SIMD[DType.float64, 4]]()
    for k in range(len(box.edge_a)):
        edges.append(corners[box.edge_b[k]] - corners[box.edge_a[k]])
    return (corners^, faces^, edges^)


def _flat() -> Triangle:
    return Triangle(Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(0, 10, 0))


def test_the_separating_axis_sweep() raises:
    var floor = _flat()
    # Falling 0.3 m onto the floor from 0.1 m: a third of the way.
    var cube = _cube(_v(0, 0, 0.6))
    var hit = _sweep_convex_triangle(
        cube[0], cube[1], cube[2], _v(0, 0, -0.3), floor
    )
    assert_almost_equal(hit.fraction, 1.0 / 3, atol=1e-12)
    assert_almost_equal(hit.normal[2], 1, atol=1e-12)
    # Wholly behind the face, moving away, too far, or passing beside.
    var below = _cube(_v(0, 0, -1))
    assert_equal(
        _sweep_convex_triangle(
            below[0], below[1], below[2], _v(0, 0, 0.2), floor
        ).fraction,
        2,
    )
    assert_equal(
        _sweep_convex_triangle(
            cube[0], cube[1], cube[2], _v(0, 0, 0.3), floor
        ).fraction,
        2,
    )
    assert_equal(
        _sweep_convex_triangle(
            cube[0], cube[1], cube[2], _v(0, 0, -0.05), floor
        ).fraction,
        2,
    )
    var beside = _cube(_v(0, -12, 0.6))
    assert_equal(
        _sweep_convex_triangle(
            beside[0], beside[1], beside[2], _v(0, 1, -1), floor
        ).fraction,
        2,
    )
    # Sliding level above the floor: never closer, so never a hit.
    assert_equal(
        _sweep_convex_triangle(
            cube[0], cube[1], cube[2], _v(5, 0, 0), floor
        ).fraction,
        2,
    )
    # Resting on the floor and sliding: touching, but not closing.
    var resting = _cube(_v(0, 0, 0.5))
    assert_equal(
        _sweep_convex_triangle(
            resting[0], resting[1], resting[2], _v(5, 0, 0), floor
        ).fraction,
        2,
    )
    # Resting and pressing down: a contact now, along the floor normal.
    var pressed = _sweep_convex_triangle(
        resting[0], resting[1], resting[2], _v(1, 0, -1), floor
    )
    assert_equal(pressed.fraction, 0)
    assert_almost_equal(pressed.normal[2], 1, atol=1e-12)


def test_an_edge_meets_a_vertical_fin() raises:
    # A thin vertical triangle, a fin along y at x = 0, faces +x. A cube
    # turned 45 degrees about z leads with an edge and closes at 1 m/s
    # from 1 m: its edge, 0.5 sqrt(2) from its center, meets the fin.
    var fin = Triangle(Vector3(0, -1, -1), Vector3(0, 1, -1), Vector3(0, 0, 1))
    var box = Polyhedron.box(Vector3(0.5, 0.5, 0.5))
    var turn = Quaternion(0, 0, Float32(sin(0.3926990817)), Float32(cos(0.3926990817)))
    var corners = List[SIMD[DType.float64, 4]]()
    for corner in box.vertices:
        var at = turn.rotate(corner)
        corners.append(_v(Float64(at.x) + 1, Float64(at.y), Float64(at.z)))
    var faces = List[SIMD[DType.float64, 4]]()
    for normal in box.normals:
        var at = turn.rotate(normal)
        faces.append(_v(Float64(at.x), Float64(at.y), Float64(at.z)))
    var edges = List[SIMD[DType.float64, 4]]()
    for k in range(len(box.edge_a)):
        edges.append(corners[box.edge_b[k]] - corners[box.edge_a[k]])
    var hit = _sweep_convex_triangle(corners, faces, edges, _v(-1, 0, 0), fin)
    assert_almost_equal(hit.fraction, 1 - 0.7071067811865476, atol=1e-6)
    assert_almost_equal(hit.normal[0], 1, atol=1e-6)


def _floor() raises -> RigidBody:
    return RigidBody(
        STATIC,
        Shape.mesh([_flat()]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _box(z: Float32, velocity: Vector3, bounce: Float32 = 0) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(0.5), Length(0.5), Length(0.5)),
        Mass(1),
        Vector3(0, 0, z),
        Quaternion.identity(),
    )
    var locked = Matrix3()
    locked.elements[0] = 0
    locked.elements[4] = 0
    locked.elements[8] = 0
    body.set_inverse_inertia(locked)
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0.5, bounce)
    return body^


def _world() -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    return world^


def test_a_falling_box_lands_and_bounces() raises:
    # From 0.1 m above the floor at 30 m/s: contact at 1/300 s of 0.01 s.
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        _ = world.add_body(_floor())
        _ = world.add_body(_box(0.6, Vector3(0, 0, -30), bounce))
        world.step(Duration(0.01))
        ref box = world.bodies[1]
        assert_almost_equal(box.linear_velocity.z, 30 * bounce, atol=1e-4)
        assert_almost_equal(box.position.z, 0.5 + 0.2 * bounce, atol=1e-5)
        assert_equal(world.contact_count, 1)
    # The discrete mode lets the same box sink into the floor.
    var discrete = _world()
    discrete.collision_detection = PhysicsWorld().collision_detection
    _ = discrete.add_body(_floor())
    _ = discrete.add_body(_box(0.6, Vector3(0, 0, -30)))
    discrete.step(Duration(0.01))
    assert_true(discrete.bodies[1].position.z < 0.45)


def test_friction_stops_a_sliding_landing() raises:
    # Friction 0.5 on a 30 m/s plastic landing removes up to 15 m/s of
    # the 5 m/s slide: the box stops sliding.
    var world = _world()
    _ = world.add_body(_floor())
    _ = world.add_body(_box(0.6, Vector3(5, 0, -30)))
    world.step(Duration(0.01))
    assert_almost_equal(world.bodies[1].linear_velocity.x, 0, atol=1e-5)
    assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-5)


def test_a_hull_on_an_indexed_floor_matches_the_full_scan() raises:
    # A tetrahedron hull falls onto a 32-triangle floor that builds a tree.
    var results = List[Float32]()
    for brute in [False, True]:
        var world = _world()
        world._ccd_brute_force = brute
        var triangles = List[Triangle]()
        for row in range(4):
            for column in range(4):
                var x = Float32(column) * 4 - 8
                var y = Float32(row) * 4 - 8
                triangles.append(
                    Triangle(
                        Vector3(x, y, 0),
                        Vector3(x + 4, y, 0),
                        Vector3(x, y + 4, 0),
                    )
                )
                triangles.append(
                    Triangle(
                        Vector3(x + 4, y, 0),
                        Vector3(x + 4, y + 4, 0),
                        Vector3(x, y + 4, 0),
                    )
                )
        _ = world.add_body(
            RigidBody(
                STATIC,
                Shape.mesh(triangles^),
                Mass(0),
                Vector3(0, 0, 0),
                Quaternion.identity(),
            )
        )
        var off = _floor()
        off.collides = False
        _ = world.add_body(off^)
        var hull = RigidBody(
            DYNAMIC,
            Shape.convex(
                [
                    Vector3(0, 0, -0.5),
                    Vector3(0.5, 0, 0.5),
                    Vector3(-0.5, 0.5, 0.5),
                    Vector3(-0.5, -0.5, 0.5),
                ]
            ),
            Mass(1),
            Vector3(0.25, 0.25, 0.75),
            Quaternion.identity(),
        )
        var locked = Matrix3()
        locked.elements[0] = 0
        locked.elements[4] = 0
        locked.elements[8] = 0
        hull.set_inverse_inertia(locked)
        hull.linear_velocity = Vector3(0, 0, -30)
        hull.material = PhysicsMaterial(0, 0)
        _ = world.add_body(hull^)
        world.step(Duration(0.01))
        # Its lowest corner, 0.5 m below its origin, rests on the floor.
        assert_almost_equal(world.bodies[2].position.z, 0.5, atol=1e-5)
        results.append(world.bodies[2].position.z)
    assert_equal(results[0], results[1])


def test_boxes_fail_closed() raises:
    # A turning box, a box that reaches another moving body, and one
    # impact too many all refuse the step and leave it unchanged.
    var world = _world()
    _ = world.add_body(_floor())
    var turning = _box(0.6, Vector3(0, 0, -30))
    turning.angular_velocity = Vector3(0, 0, 1)
    _ = world.add_body(turning^)
    with assert_raises(contains="box or hull that cannot turn"):
        world.step(Duration(0.01))
    assert_equal(world.bodies[1].position.z, 0.6)
    var pair = _world()
    _ = pair.add_body(_box(0.6, Vector3(0, 0, -30)))
    _ = pair.add_body(_box(2, Vector3(0, 0, 0)))
    with assert_raises(contains="must not reach another moving body"):
        pair.step(Duration(0.01))
    var limited = _world()
    limited.ccd_max_impacts = 1
    _ = limited.add_body(_floor())
    var ceiling = Triangle(
        Vector3(-10, -10, 1.3), Vector3(0, 10, 1.3), Vector3(10, -10, 1.3)
    )
    _ = limited.add_body(
        RigidBody(
            STATIC,
            Shape.mesh([ceiling]),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    # Elastic between a floor and a ceiling 0.3 m apart at the box's
    # faces: at 60 m/s it bounces more than once in 0.02 s.
    _ = limited.add_body(_box(0.65, Vector3(0, 0, -60), 1))
    with assert_raises(contains="impact limit exhausted"):
        limited.step(Duration(0.02))
    assert_equal(limited.bodies[2].position.z, 0.65)


def test_exact_end_empty_world_split_spin_and_a_sunk_box() raises:
    # Exact binary values: 0.25 m above the floor at 1 m/s for 0.25 s
    # lands exactly at the end of the step.
    var world = _world()
    _ = world.add_body(_floor())
    _ = world.add_body(_box(0.75, Vector3(0, 0, -1)))
    world.step(Duration(0.25))
    assert_equal(world.bodies[1].position.z, 0.5)
    assert_equal(world.contact_count, 1)
    # With no triangles at all, the box flies on.
    var empty = _world()
    _ = empty.add_body(_box(0.75, Vector3(0, 0, -1)))
    empty.step(Duration(0.25))
    assert_equal(empty.bodies[0].position.z, 0.5)
    # A split-correction spin turns a box, which is refused.
    var pushed = _world()
    var box = _box(0.75, Vector3(0, 0, 0))
    box.push_angular = Vector3(0, 1, 0)
    _ = pushed.add_body(box^)
    with assert_raises(contains="box or hull that cannot turn"):
        pushed.step(Duration(0.25))
    # A box sunk 5 cm into the floor, at rest: its lower corners are
    # behind the face, its upper ones in front, and the contact solver
    # pushes it up without a sweep impact.
    var sunk = _world()
    _ = sunk.add_body(_floor())
    _ = sunk.add_body(_box(0.45, Vector3(0, 0, 0)))
    sunk.step(Duration(0.01))
    assert_true(sunk.bodies[1].position.z >= 0.45)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
