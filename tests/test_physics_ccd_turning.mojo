# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Turning capsules and offset spheres under CCD.

The sweep advances in sub-steps that a second-order bound certifies. The
checks here use their own geometry: the exact turn at a constant spin,
and the lowest point of a capsule over a flat floor.
"""

from extensions.physics.body import DYNAMIC, KINEMATIC, STATIC, RigidBody
from extensions.physics.ccd import (
    SPHERE_MESH_CCD,
    _segment_triangle_gap,
    _triangle_closest,
    _turning_step,
)
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, sin, sqrt
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


def _flat() -> Triangle:
    return Triangle(
        Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(0, 10, 0)
    )


def test_the_closest_point_on_a_triangle() raises:
    var a = _v(0, 0, 0)
    var b = _v(1, 0, 0)
    var c = _v(0, 1, 0)
    # Over the face, then nearest each edge and each corner.
    var inside = _triangle_closest(_v(0.25, 0.25, 2), a, b, c)
    assert_true(inside == _v(0.25, 0.25, 0))
    assert_true(_triangle_closest(_v(0.5, -1, 0), a, b, c) == _v(0.5, 0, 0))
    assert_true(_triangle_closest(_v(1, 1, 0), a, b, c) == _v(0.5, 0.5, 0))
    assert_true(_triangle_closest(_v(-1, 0.5, 0), a, b, c) == _v(0, 0.5, 0))
    assert_true(_triangle_closest(_v(-1, -1, 0), a, b, c) == a)
    assert_true(_triangle_closest(_v(3, -1, 0), a, b, c) == b)


def test_the_gap_from_a_segment_to_a_triangle() raises:
    var triangle = _flat()
    # An end above the face.
    var g = _segment_triangle_gap(_v(0, 0, 1), _v(1, 0, 1), triangle)
    assert_almost_equal(g[0], 1, atol=1e-12)
    assert_almost_equal(g[1][2], 1, atol=1e-12)
    # Beside an edge: the segment's interior is nearest.
    g = _segment_triangle_gap(_v(-1, -12, 1), _v(2, 0, 0), triangle)
    assert_almost_equal(g[0], sqrt(Float64(5)), atol=1e-12)
    assert_almost_equal(g[2][1], -12, atol=1e-12)
    # A segment that crosses the face.
    g = _segment_triangle_gap(_v(0, 0, -1), _v(0, 0, 2), triangle)
    assert_equal(g[0], 0)
    assert_almost_equal(g[2][2], 0, atol=1e-12)
    # An end on the face, and a segment on an edge's line.
    g = _segment_triangle_gap(_v(0, 0, 0), _v(0, 0, 1), triangle)
    assert_equal(g[0], 0)
    assert_almost_equal(g[1][2], 1, atol=1e-12)
    g = _segment_triangle_gap(_v(0, -11, -1), _v(0, 2, 2), triangle)
    assert_equal(g[0], 0)
    # Crossings of the face's plane outside each edge.
    for start in [_v(0, -12, -1), _v(8, 5, -1), _v(-8, 5, -1)]:
        g = _segment_triangle_gap(start, _v(0, 0, 2), triangle)
        assert_true(g[0] > 0)
    # A segment beside the face that does not cross it.
    g = _segment_triangle_gap(_v(30, 0, -1), _v(0, 0, 2), triangle)
    assert_true(g[0] > 10)


def test_the_turning_step_bound() raises:
    var triangle = _flat()
    var still = (_v(0, 0, 0), _v(0, 0, 0))
    # Partly behind, at rest: no limit, because the depth cannot grow.
    assert_equal(
        _turning_step(
            (_v(0, 0, -1), _v(1, 0, 1)), still, 0.1, 1e-4, 0, triangle
        ),
        1e300,
    )
    assert_equal(
        _turning_step(
            (_v(0, 0, -1), _v(1, 0, -1)), still, 0.1, 1e-4, 0, triangle
        ),
        -1,
    )
    # Overlapping by 0.05: at rest no limit; closing at 1 m/s it may
    # deepen by the tolerance only.
    assert_equal(
        _turning_step(
            (_v(0, 0, 0.05), _v(1, 0, 1)), still, 0.1, 1e-4, 0, triangle
        ),
        1e300,
    )
    assert_almost_equal(
        _turning_step(
            (_v(0, 0, 0.05), _v(1, 0, 1)),
            (_v(0, 0, -1), _v(0, 0, -1)),
            0.1,
            1e-4,
            0,
            triangle,
        ),
        1e-4,
        atol=1e-12,
    )
    # Moving away or not at all, with no turn: no limit.
    assert_equal(
        _turning_step(
            (_v(0, 0, 1), _v(1, 0, 1)), still, 0.1, 1e-4, 0, triangle
        ),
        1e300,
    )
    # Closing at 1 m/s from 0.9 m of room: 0.9001 s.
    var falling = (_v(0, 0, -1), _v(0, 0, -1))
    assert_almost_equal(
        _turning_step(
            (_v(0, 0, 1), _v(1, 0, 1)), falling, 0.1, 1e-4, 0, triangle
        ),
        0.9001,
        atol=1e-12,
    )
    # Resting within the tolerance and turning: sqrt(2 tol / curvature).
    assert_almost_equal(
        _turning_step(
            (_v(0, 0, 0.1), _v(1, 0, 0.1)), still, 0.1, 1e-4, 2, triangle
        ),
        0.01,
        atol=1e-12,
    )
    # Beside the triangle, past an edge: its side plane separates most.
    var beside = _turning_step(
        (_v(0, -12, 0), _v(1, -12, 0)),
        (_v(0, 1, 0), _v(0, 1, 0)),
        0.1,
        1e-4,
        0,
        triangle,
    )
    assert_almost_equal(beside, 1.9001, atol=1e-9)


def _floor() raises -> RigidBody:
    var triangles = List[Triangle]()
    for row in range(4):
        for column in range(4):
            var x = Float32(column) * 5 - 10
            var y = Float32(row) * 5 - 10
            triangles.append(
                Triangle(
                    Vector3(x, y, 0), Vector3(x + 5, y, 0), Vector3(x, y + 5, 0)
                )
            )
            triangles.append(
                Triangle(
                    Vector3(x + 5, y, 0),
                    Vector3(x + 5, y + 5, 0),
                    Vector3(x, y + 5, 0),
                )
            )
    return RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _capsule(at: Vector3, turn: Quaternion) raises -> RigidBody:
    # Radius 0.1 m, half height 0.4 m, 1 kg, a solid rod's inertia.
    var body = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(0.1), Length(0.4)),
        Mass(1),
        at,
        turn,
    )
    var inverse = Matrix3()
    inverse.elements[0] = 15
    inverse.elements[4] = 15
    inverse.elements[8] = 200
    body.set_inverse_inertia(inverse)
    body.material = PhysicsMaterial(0.5, 0.5)
    return body^


def _world(brute: Bool = False) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    _ = world.add_body(_floor())
    return world^


def _lowest(body: RigidBody) -> Float64:
    # The lowest point of a capsule: its lower axis end less the radius.
    var half = body.shape_world_rotation().rotate(
        Vector3(0, 0, body.shape.half_height)
    )
    var at = body.shape_world_position()
    return min(Float64(at.z - half.z), Float64(at.z + half.z)) - Float64(
        body.shape.radius
    )


def test_a_free_turn_is_the_exact_turn() raises:
    # Far from the floor, the pose turns by |w| h about w exactly.
    var world = _world()
    var body = _capsule(Vector3(0, 0, 50), Quaternion.identity())
    body.angular_velocity = Vector3(0, 3, 0)
    body.linear_velocity = Vector3(1, 0, 0)
    _ = world.add_body(body^)
    world.step(Duration(0.1))
    ref moved = world.bodies[1]
    assert_almost_equal(moved.rotation.y, Float32(sin(0.15)), atol=1e-6)
    assert_almost_equal(moved.rotation.w, Float32(cos(0.15)), atol=1e-6)
    assert_almost_equal(moved.position.x, 0.1, atol=1e-6)
    assert_equal(moved.angular_velocity.y, 3)
    assert_equal(world.contact_count, 0)


def test_a_rolling_capsule_does_not_creep() raises:
    # A capsule lies on the floor along x, spins about its own axis and
    # slides along y. It never approaches the floor, so the second-order
    # bound lets it finish in a few sub-steps with no impact.
    var world = _world()
    world.ccd_max_substeps = 8
    var lying = Quaternion(0, Float32(sqrt(0.5)), 0, Float32(sqrt(0.5)))
    var body = _capsule(Vector3(0, 0, 0.1), lying)
    body.angular_velocity = Vector3(20, 0, 0)
    body.linear_velocity = Vector3(0, 2, 0)
    _ = world.add_body(body^)
    world.step(Duration(0.01))
    assert_true(_lowest(world.bodies[1]) >= -0.1 / 1024 - 1e-6)
    assert_almost_equal(world.bodies[1].position.y, 0.02, atol=1e-6)
    # No impulse: the spin and the slide are unchanged.
    assert_almost_equal(world.bodies[1].angular_velocity.x, 20, atol=1e-4)
    assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-4)


def test_a_tumbling_capsule_lands_on_its_end() raises:
    for brute in [False, True]:
        var world = _world(brute)
        var tilted = Quaternion(Float32(sin(0.3)), 0, 0, Float32(cos(0.3)))
        var body = _capsule(Vector3(0, 0, 0.8), tilted)
        body.angular_velocity = Vector3(4, 0, 0)
        body.linear_velocity = Vector3(0, 0, -30)
        _ = world.add_body(body^)
        var before = 30.0 * 30 + 16.0 / 15
        world.step(Duration(0.02))
        ref landed = world.bodies[1]
        assert_true(
            _lowest(landed) >= -0.1 / 1024 - 1e-5, String(_lowest(landed))
        )
        assert_true(world.contact_count >= 1)
        assert_true(landed.linear_velocity.z > -30)
        var v = landed.linear_velocity
        var w = landed.angular_velocity
        # Twice the energy, in the tensor of the step's start pose.
        var turn = Quaternion(Float32(sin(0.3)), 0, 0, Float32(cos(0.3)))
        var local = turn.conjugate().rotate(w)
        var after = (
            Float64(v.dot(v))
            + (Float64(local.x * local.x) + Float64(local.y * local.y)) / 15
            + Float64(local.z * local.z) / 200
        )
        assert_true(after <= before * 1.000001)


def test_an_offset_sphere_swings_into_a_wall() raises:
    # A sphere 1 m from its body's center swings about z into a wall at
    # x = 1.3. The sweep stops it there.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(
                [
                    # Its front faces -x, toward the sphere.
                    Triangle(
                        Vector3(1.3, -5, -5),
                        Vector3(1.3, 0, 5),
                        Vector3(1.3, 5, -5),
                    )
                ]
            ),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    var arm = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    arm.set_shape_pose(Vector3(0, -1, 0), Quaternion.identity())
    # The mass stays at the body's origin, 1 m from the sphere.
    arm.set_center_of_mass(Vector3(0, 0, 0))
    arm.linear_velocity = Vector3(20, 0, 0)
    arm.angular_velocity = Vector3(0, 0, 10)
    arm.material = PhysicsMaterial(0, 0)
    _ = world.add_body(arm^)
    world.step(Duration(0.05))
    var sphere = world.bodies[1].shape_world_position()
    assert_true(sphere.x <= 1.2 + 0.1 / 1024 + 1e-5, String(sphere.x))
    assert_true(world.contact_count >= 1)


def test_budgets_and_neighbors_fail_closed() raises:
    # A capsule that lies on the floor and turns about the vertical needs
    # many sub-steps; one cannot finish the step, which rolls back.
    var world = _world()
    world.ccd_max_substeps = 1
    var lying = Quaternion(0, Float32(sqrt(0.5)), 0, Float32(sqrt(0.5)))
    var body = _capsule(Vector3(0, 0, 0.1), lying)
    body.angular_velocity = Vector3(0, 0, 200)
    _ = world.add_body(body^)
    with assert_raises(contains="sub-step limit exhausted"):
        world.step(Duration(0.01))
    assert_equal(world.bodies[1].position.z, 0.1)
    world.ccd_max_substeps = 0
    with assert_raises(contains="sub-step limit must be"):
        world.step(Duration(0.01))
    # One impact cannot land a tumbling capsule that bounces twice.
    var bounce = _world()
    bounce.ccd_max_impacts = 1
    var tilted = Quaternion(Float32(sin(0.3)), 0, 0, Float32(cos(0.3)))
    var falling = _capsule(Vector3(0, 0, 0.8), tilted)
    falling.angular_velocity = Vector3(40, 0, 0)
    falling.linear_velocity = Vector3(0, 0, -30)
    falling.material = PhysicsMaterial(0, 0)
    _ = bounce.add_body(falling^)
    with assert_raises(contains="impact limit exhausted"):
        bounce.step(Duration(0.1))
    # A turning body can share a group with another moving body.
    var pair = _world()
    _ = pair.add_body(_capsule(Vector3(0, 0, 2), Quaternion.identity()))
    var ball = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 2.6),
        Quaternion.identity(),
    )
    _ = pair.add_body(ball^)
    pair.step(Duration(0.01))
    assert_true(pair.bodies[2].position.z > pair.bodies[1].position.z)


def test_a_straight_slow_drop_and_skipped_triangles() raises:
    # An upright turning capsule with no spin drops straight at 0.5 m/s:
    # no curvature, no slip and no bounce. A disabled mesh beside it, and
    # a mesh at z = 1 whose front faces up, above its axis, take no part.
    var world = _world()
    var off = _floor()
    off.position.z = 0.05
    off.collides = False
    _ = world.add_body(off^)
    var above = RigidBody(
        STATIC,
        Shape.mesh(
            [Triangle(Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(0, 1, 1))]
        ),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    _ = world.add_body(above^)
    var body = _capsule(Vector3(0, 0, 0.52), Quaternion.identity())
    body.linear_velocity = Vector3(0, 0, -0.5)
    _ = world.add_body(body^)
    world.step(Duration(0.1))
    ref landed = world.bodies[3]
    assert_true(_lowest(landed) >= -0.1 / 1024 - 1e-6)
    assert_almost_equal(landed.linear_velocity.z, 0, atol=1e-5)
    assert_equal(landed.angular_velocity.x, 0)
    assert_true(world.contact_count >= 1)


def test_a_sphere_off_its_mass_center_turns() raises:
    # A sphere centered on its body, with its mass 0.5 m to the side,
    # turns about the mass; far from the floor it keeps the exact turn.
    var world = _world()
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 50),
        Quaternion.identity(),
    )
    body.set_center_of_mass(Vector3(0.5, 0, 0))
    body.angular_velocity = Vector3(0, 0, 2)
    _ = world.add_body(body^)
    world.step(Duration(0.1))
    var sphere = world.bodies[1].shape_world_position()
    # The sphere circles the mass center, 0.5 m away, by 0.2 rad.
    assert_almost_equal(sphere.x, Float32(0.5 - 0.5 * cos(0.2)), atol=1e-5)
    assert_almost_equal(sphere.y, Float32(-0.5 * sin(0.2)), atol=1e-5)


def test_more_refused_settings() raises:
    var world = _world()
    _ = world.add_body(_capsule(Vector3(0, 0, 5), Quaternion.identity()))
    world.ccd_max_substeps = 70000
    with assert_raises(contains="sub-step limit must be"):
        world.step(Duration(0.01))
    world.ccd_max_substeps = 256
    world.bodies[1].set_center_of_mass(Vector3(20000, 0, 0))
    with assert_raises(contains="offsets must be at most"):
        world.step(Duration(0.01))
    var kinematic = _world()
    var sphere = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 5),
        Quaternion.identity(),
    )
    sphere.set_shape_pose(Vector3(0.2, 0, 0), Quaternion.identity())
    sphere.set_center_of_mass(Vector3(0, 0, 0))
    sphere.set_kind(KINEMATIC)
    sphere.linear_velocity = Vector3(1, 0, 0)
    sphere.angular_velocity = Vector3(0, 0, 2)
    _ = kinematic.add_body(sphere^)
    # An offset, spinning kinematic sphere is supported. Alone, it follows
    # the integrator, and it still keeps the offset limit.
    kinematic.step(Duration(0.01))
    assert_almost_equal(kinematic.bodies[1].position.x, 0.01, atol=1e-6)
    kinematic.bodies[1].shape_position = Vector3(20000, 0, 0)
    with assert_raises(contains="offsets must be at most"):
        kinematic.step(Duration(0.01))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
