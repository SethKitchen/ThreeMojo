# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent geometric and lifecycle controls for sphere/mesh CCD."""

from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    STATIC,
    KINEMATIC,
    RigidBody,
)
from extensions.physics.ccd import (
    CollisionDetection,
    DISCRETE,
    SPHERE_MESH_CCD,
    _root,
    _choose,
    _SweepHit,
    _sweep_triangle,
)
from extensions.physics.shape import Shape, PhysicsMaterial, _wide
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_true,
    assert_false,
    assert_equal,
    assert_almost_equal,
    assert_raises,
)
from units.si import Length, Mass, Duration


def _ball(
    radius: Float32, z: Float32, velocity: Float32, bounce: Float32 = 0
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(radius)),
        Mass(1),
        Vector3(0, 0, z),
        Quaternion.identity(),
    )
    body.linear_velocity = Vector3(0, 0, velocity)
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _floor(z: Float32 = 0, ceiling: Bool = False) raises -> RigidBody:
    var a = Vector3(-100, -100, z)
    var b = Vector3(100, -100, z)
    var c = Vector3(0, 100, z)
    var triangle = Triangle(a, b, c)
    if ceiling:
        triangle = Triangle(a, c, b)
    return RigidBody(
        STATIC,
        Shape.mesh([triangle]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _world(
    radius: Float32 = 0.1,
    z: Float32 = 0.15,
    velocity: Float32 = -30,
    bounce: Float32 = 0,
) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    _ = world.add_body(_floor())
    _ = world.add_body(_ball(radius, z, velocity, bounce))
    return world^


def test_issue_reproducer_and_discrete_control() raises:
    var world = _world()
    world.step(Duration(0.01))
    assert_almost_equal(world.bodies[1].position.z, 0.1, atol=1e-7)
    assert_equal(world.bodies[1].linear_velocity.z, 0)
    assert_equal(world.contact_count, 1)
    assert_equal(len(world.events), 2)
    assert_almost_equal(world.events[0].normal_impulse.z, 30, atol=1e-6)
    for _ in range(3):
        world.step(Duration(0.01))
        assert_almost_equal(world.bodies[1].position.z, 0.1, atol=1e-7)
    var discrete = _world()
    discrete.collision_detection = DISCRETE
    discrete.step(Duration(0.01))
    assert_almost_equal(discrete.bodies[1].position.z, -0.15, atol=1e-7)
    assert_equal(discrete.contact_count, 0)


def test_plane_family_reference() raises:
    # Travel to contact, then e times the remaining normal travel back out.
    for radius in [Float32(0.01), Float32(0.1), Float32(1), Float32(10)]:
        for velocity in [
            Float32(-3),
            Float32(-30),
            Float32(-300),
            Float32(-3000),
        ]:
            for dt in [Float32(0.001), Float32(0.01), Float32(0.1)]:
                var start = radius + max(Float32(0.03), -velocity * dt * 0.25)
                for bounce in [Float32(0), Float32(0.3), Float32(1)]:
                    var world = _world(radius, start, velocity, bounce)
                    world.step(Duration(dt))
                    var gap = Float64(start) - Float64(radius)
                    var travel = -Float64(velocity) * Float64(dt)
                    var expected = Float64(start) - travel
                    var expected_v = Float64(velocity)
                    if travel >= gap:
                        expected = Float64(radius) + Float64(bounce) * (
                            travel - gap
                        )
                        expected_v = -Float64(bounce) * Float64(velocity)
                    assert_almost_equal(
                        Float64(world.bodies[1].position.z),
                        expected,
                        atol=max(1e-6, abs(expected) * 2e-7),
                    )
                    assert_almost_equal(
                        Float64(world.bodies[1].linear_velocity.z),
                        expected_v,
                        atol=1e-4,
                    )
                    assert_true(
                        abs(world.bodies[1].linear_velocity.z) <= -velocity
                    )


def test_edge_vertex_and_grazing_reference() raises:
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
    )
    # Edge y=0, x=2: circle section gives z=sqrt(r*r-y*y).
    for y in [Float32(-0.1), Float32(-0.6), Float32(-0.999)]:
        var hit = _sweep_triangle(
            _wide(Vector3(2, y, 2)), _wide(Vector3(0, 0, -4)), 1, triangle
        )
        var z = sqrt(1 - Float64(y) * Float64(y))
        assert_almost_equal(hit.fraction, (2 - z) / 4, atol=1e-12)
        assert_almost_equal(hit.normal[1], Float64(y), atol=1e-12)
        assert_almost_equal(hit.normal[2], z, atol=1e-12)
    # Vertex at the origin, where both adjacent edge projections are outside.
    var vertex = _sweep_triangle(
        _wide(Vector3(-0.6, -0.6, 2)), _wide(Vector3(0, 0, -4)), 1, triangle
    )
    var corner_z = sqrt(1 - 2 * Float64(Float32(0.6)) ** 2)
    assert_almost_equal(vertex.fraction, (2 - corner_z) / 4, atol=1e-12)
    # Exact grazing gives no impulse; just inside is covered above.
    assert_equal(
        _sweep_triangle(
            _wide(Vector3(2, -1, 2)), _wide(Vector3(0, 0, -4)), 1, triangle
        ).fraction,
        2,
    )
    assert_equal(
        _sweep_triangle(
            _wide(Vector3(2, -1.001, 2)), _wide(Vector3(0, 0, -4)), 1, triangle
        ).fraction,
        2,
    )
    # A lateral path reaches the rounded edge, while staying above the plane.
    var lateral = _sweep_triangle(
        _wide(Vector3(2, -2, 0.6)), _wide(Vector3(0, 4, 0)), 1, triangle
    )
    var edge_y = sqrt(1 - Float64(Float32(0.6)) ** 2)
    assert_almost_equal(lateral.fraction, (2 - edge_y) / 4, atol=1e-12)


def test_more_than_one_impact_and_limit_rollback() raises:
    var world = _world(0.1, 0.5, -300, 1)
    _ = world.add_body(_floor(1, True))
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 4)
    assert_equal(len(world.events), 8)
    assert_almost_equal(world.bodies[1].position.z, 0.7, atol=1e-6)
    assert_equal(world.bodies[1].linear_velocity.z, -300)
    var failed = _world(0.1, 0.5, -300, 1)
    _ = failed.add_body(_floor(1, True))
    failed.ccd_max_impacts = 3
    failed.bodies[1].force = Vector3(1, 2, 3)
    failed.contact_count = 77
    var order = failed._order.copy()
    with assert_raises():
        failed.step(Duration(0.01))
    assert_equal(failed.bodies[1].position.z, 0.5)
    assert_equal(failed.bodies[1].linear_velocity.z, -300)
    assert_true(failed.bodies[1].force == Vector3(1, 2, 3))
    assert_equal(failed.contact_count, 77)
    assert_equal(len(failed.events), 0)
    assert_equal(failed._order, order)


def test_slow_overlap_and_backface_controls() raises:
    for start in [Float32(0.09), Float32(0.1), Float32(0.115), Float32(1)]:
        for velocity in [Float32(-0.1), Float32(0), Float32(0.1)]:
            var ccd = _world(0.1, start, velocity)
            var discrete = _world(0.1, start, velocity)
            discrete.collision_detection = DISCRETE
            ccd.step(Duration(0.01))
            discrete.step(Duration(0.01))
            assert_true(ccd.bodies[1].position == discrete.bodies[1].position)
            assert_true(
                ccd.bodies[1].linear_velocity
                == discrete.bodies[1].linear_velocity
            )
            assert_equal(ccd.contact_count, discrete.contact_count)
    for velocity in [Float32(-30), Float32(30)]:
        var back = _world(0.1, -0.15, velocity)
        back.step(Duration(0.01))
        assert_almost_equal(
            back.bodies[1].position.z, -0.15 + velocity * 0.01, atol=1e-7
        )
        assert_equal(back.contact_count, 0)


def test_ghosts_modes_and_reentry() raises:
    var world = _world()
    world.bodies[1].collides = False
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 0)
    world.bodies[1].position = Vector3(0, 0, 0.15)
    world.bodies[1].collides = True
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 1)
    world.bodies[0].collides = False
    world.bodies[1].position = Vector3(0, 0, 0.15)
    world.bodies[1].linear_velocity = Vector3(0, 0, -30)
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 0)
    world.bodies[0].collides = True
    world.bodies[1].set_kind(KINEMATIC)
    with assert_raises():
        world.step(Duration(0.01))
    world.bodies[1].collides = False
    world.step(Duration(0.01))
    world.bodies[1].set_kind(STATIC)
    world.step(Duration(0.01))
    world.bodies[1].set_kind(DYNAMIC)
    world.bodies[1].collides = True
    world.bodies[1].position = Vector3(0, 0, 0.15)
    world.bodies[1].linear_velocity = Vector3(0, 0, -30)
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 1)


def test_support_and_finite_failures_are_atomic() raises:
    assert_true(DISCRETE.is_valid())
    assert_true(SPHERE_MESH_CCD.is_valid())
    assert_false(CollisionDetection(-1).is_valid())
    assert_false(CollisionDetection(2).is_valid())
    for choice in range(17):
        var world = _world()
        world.bodies[1].force = Vector3(1, 2, 3)
        if choice == 0:
            world.collision_detection = CollisionDetection(7)
        elif choice == 1:
            world.ccd_max_impacts = 0
        elif choice == 2:
            world.ccd_max_impacts = 1025
        elif choice == 3:
            world.bodies[1].shape = Shape.capsule(Length(0.1), Length(0.2))
        elif choice == 4:
            world.bodies[1].shape_position = Vector3(1, 0, 0)
        elif choice == 5:
            world.bodies[1].center_of_mass = Vector3(1, 0, 0)
        elif choice == 6:
            var inertia = world.bodies[1].inverse_inertia()
            inertia.elements[4] *= 2
            world.bodies[1].set_inverse_inertia(inertia)
        elif choice == 7:
            var inertia = Matrix3()
            inertia.elements[0] = 0
            inertia.elements[4] = 0
            inertia.elements[8] = 0
            world.bodies[1].set_inverse_inertia(inertia)
        elif choice == 8:
            world.bodies[1].shape.radius = 0
        elif choice == 9:
            world.bodies[1].shape.radius = inf[DType.float32]()
        elif choice == 10:
            world.gravity = Vector3(nan[DType.float32](), 0, 0)
        elif choice == 11:
            world.bodies[0].linear_velocity = Vector3(1, 0, 0)
        elif choice == 12:
            world.bodies[0].angular_velocity = Vector3(1, 0, 0)
        elif choice == 13:
            world._triangles[0] = Triangle(
                Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)
            )
        elif choice == 14:
            world.bodies[1].force = Vector3(1, 2, 3e38)
        elif choice == 15:
            _ = world.add_body(_ball(0.1, 0.3, 0))
        else:
            world.bounce_threshold = nan[DType.float32]()
        var position = world.bodies[1].position
        var force = world.bodies[1].force
        with assert_raises():
            world.step(Duration(10))
        assert_true(world.bodies[1].position == position)
        assert_true(world.bodies[1].force == force)
        assert_equal(world.bodies[1].linear_velocity.z, -30)


def test_energy_friction_and_spin_transfer() raises:
    for friction in [Float32(0), Float32(0.3), Float32(3)]:
        for bounce in [Float32(0), Float32(0.5), Float32(1)]:
            var world = _world(0.1, 0.3, -30, bounce)
            world.bodies[0].material = PhysicsMaterial(friction, bounce)
            world.bodies[1].material = PhysicsMaterial(friction, bounce)
            world.bodies[1].linear_velocity.x = 4
            world.bodies[1].angular_velocity = Vector3(0, 100, 0)
            var initial = 30.0 * 30 + 4 * 4 + 0.004 * 100 * 100
            world.step(Duration(0.02))
            var v = world.bodies[1].linear_velocity
            var w = world.bodies[1].angular_velocity
            var final = Float64(v.dot(v)) + 0.004 * Float64(w.dot(w))
            assert_true(final <= initial * 1.000001)
            assert_almost_equal(v.z, 30 * bounce, atol=1e-5)
            if friction == 0:
                assert_equal(v.x, 4)
                assert_equal(w.y, 100)
            else:
                assert_true(final < initial)


def test_separated_spheres_time_order_and_repeats() raises:
    var reference = List[Float32]()
    for repeat in range(3):
        var world = _world(0.1, 0.4, -30, 0.5)
        var early = _ball(0.1, 0.2, -30, 0.5)
        early.position.x = 10
        _ = world.add_body(early^)
        world.step(Duration(0.02))
        assert_equal(world.contact_count, 2)
        assert_equal(len(world.events), 4)
        assert_equal(world.events[0].body.value, 2)
        assert_equal(world.events[2].body.value, 1)
        if repeat == 0:
            reference.append(world.bodies[1].position.z)
            reference.append(world.bodies[2].position.z)
        else:
            assert_equal(world.bodies[1].position.z, reference[0])
            assert_equal(world.bodies[2].position.z, reference[1])
    # Tied hits retain body order; duplicate triangles retain insertion order.
    var tied = _world()
    _ = tied.add_body(_floor())
    var second = _ball(0.1, 0.15, -30)
    second.position.x = 10
    _ = tied.add_body(second^)
    tied.step(Duration(0.01))
    assert_equal(tied.events[0].body.value, 1)
    assert_equal(tied.events[0].other.value, 0)
    assert_equal(tied.events[2].body.value, 3)


def test_empty_free_overflow_and_endpoint_worlds() raises:
    var empty = PhysicsWorld()
    empty.collision_detection = SPHERE_MESH_CCD
    empty.step(Duration(0.01))
    assert_equal(empty.contact_count, 0)
    _ = empty.add_body(_ball(0.1, 10, 2))
    empty.gravity = Vector3(0, 0, 0)
    empty.step(Duration(0.01))
    assert_almost_equal(empty.bodies[0].position.z, 10.02, atol=1e-6)
    var endpoint = _world(0.125, 0.625, -1)
    endpoint.step(Duration(0.5))
    assert_equal(endpoint.bodies[1].position.z, 0.125)
    assert_equal(endpoint.contact_count, 1)
    # A slow impact from outside the existing contact margin does not bounce.
    var slow = _world(0.1, 0.2, -0.5, 1)
    slow.step(Duration(0.5))
    assert_equal(slow.bodies[1].linear_velocity.z, 0)
    var overflow = PhysicsWorld()
    overflow.collision_detection = SPHERE_MESH_CCD
    overflow.gravity = Vector3(0, 0, 0)
    _ = overflow.add_body(_ball(0.1, 1e38, 3e38))
    with assert_raises():
        overflow.step(Duration(2))
    assert_equal(overflow.bodies[0].position.z, Float32(1e38))
    assert_equal(overflow.bodies[0].linear_velocity.z, Float32(3e38))


def test_scalar_settings_and_extra_support_rejections() raises:
    for setting in range(4):
        for value in [Float32(-1), nan[DType.float32]()]:
            var world = _world()
            if setting == 0:
                world.margin = value
            elif setting == 1:
                world.slop = value
            elif setting == 2:
                world.push_factor = value
            else:
                world.bounce_threshold = value
            with assert_raises():
                world.step(Duration(0.01))
    for choice in range(5):
        var world = _world()
        if choice == 0:
            world.bodies[1].set_kind(STATIC)
        elif choice == 1:
            world.bodies[1].shape = Shape.box(Length(1), Length(1), Length(1))
        elif choice == 2:
            world.bodies[1].material = PhysicsMaterial(-1, 0)
        elif choice == 3:
            world.bodies[1].angular_velocity = Vector3(
                0, inf[DType.float32](), 0
            )
        else:
            world._triangles[0].a.x = nan[DType.float32]()
        with assert_raises():
            world.step(Duration(0.01))


def test_sweep_feature_controls() raises:
    var zero = _wide(Vector3(0, 0, 0))
    var up = _wide(Vector3(0, 0, 1))
    var down = -up
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
    )
    assert_equal(_root(up * 0.5, down, 1), 0)
    assert_equal(_root(up, zero, 1), 2)
    assert_equal(_root(up, up, 1), 2)
    var miss = _SweepHit(2, zero)
    assert_equal(_choose(up, down, zero, up, zero, -1, miss).fraction, 2)
    assert_equal(
        _choose(up, down, zero, up, zero, 0.5, _SweepHit(0.25, up)).fraction,
        0.25,
    )
    assert_equal(_choose(up, down * 4, zero, up, zero, 0.5, miss).fraction, 2)
    assert_equal(_choose(up, down, zero, up, zero, 1, miss).fraction, 2)
    assert_equal(_choose(up, up, zero, up, zero, 0, miss).fraction, 2)
    assert_equal(
        _sweep_triangle(
            up,
            down,
            1,
            Triangle(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)),
        ).fraction,
        2,
    )
    # Outside the other two triangle half-spaces, but within its AABB.
    var edge = _sweep_triangle(_wide(Vector3(6, 5, 2)), down * 4, 1, triangle)
    assert_true(edge.fraction <= 1)
    edge = _sweep_triangle(_wide(Vector3(-0.6, 2, 2)), down * 4, 1, triangle)
    assert_true(edge.fraction <= 1)
    # The swept AABB overlaps although the plane crossing is after this step.
    var tilted = Triangle(
        Vector3(0, 0, 0), Vector3(10, 0, 10), Vector3(0, 10, 0)
    )
    assert_equal(
        _sweep_triangle(_wide(Vector3(1, 1, 5)), down, 0.1, tilted).fraction, 2
    )


def test_oblique_plastic_contact_does_not_repeat() raises:
    var world = PhysicsWorld()
    world.collision_detection = SPHERE_MESH_CCD
    world.gravity = Vector3(0, 0, 0)
    var triangle = Triangle(
        Vector3(-10, -10, -20), Vector3(10, -10, 0), Vector3(0, 10, 10)
    )
    var ground = RigidBody(
        STATIC,
        Shape.mesh([triangle]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    ground.material = PhysicsMaterial(0, 0)
    _ = world.add_body(ground^)
    var body = _ball(1, Float32(2 / sqrt(3.0)), 0)
    body.position.x = -body.position.z
    body.position.y = -body.position.z
    body.linear_velocity = Vector3(10, 0, -30)
    _ = world.add_body(body^)
    world.step(Duration(0.1))
    assert_equal(world.contact_count, 1)
    var v = world.bodies[1].linear_velocity
    assert_almost_equal(v.x, -10.0 / 3, atol=1e-6)
    assert_almost_equal(v.y, -40.0 / 3, atol=1e-6)
    assert_almost_equal(v.z, -50.0 / 3, atol=1e-6)


def test_long_travel_feature_root_and_bound() raises:
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
    )
    for distance in [Float32(1e4), Float32(1e7), Float32(1e8), Float32(1e9)]:
        var offset = _wide(Vector3(-distance, -0.5, 0.5))
        var travel = _wide(Vector3(2 * distance, 0, 0))
        var expected = (Float64(distance) - sqrt(0.5)) / (2 * Float64(distance))
        assert_almost_equal(_root(offset, travel, 1), expected, atol=1e-15)
        if distance <= 1048576:
            var hit = _sweep_triangle(offset, travel, 1, triangle)
            assert_almost_equal(hit.fraction, expected, atol=1e-15)
            assert_almost_equal(hit.normal[0], -sqrt(0.5), atol=2e-7)
        else:
            with assert_raises():
                _ = _sweep_triangle(offset, travel, 1, triangle)
    var large = Triangle(
        Vector3(-1e16, -1e16, -2e16),
        Vector3(1e16, -1e16, 0),
        Vector3(0, 1e16, 1e16),
    )
    with assert_raises():
        _ = _sweep_triangle(
            _wide(Vector3(-1.1547005, -1.1547005, 1.1547005)),
            _wide(Vector3(1, 0, -3)),
            1,
            large,
        )
    var bounded = _world()
    bounded.bodies[1].linear_velocity = Vector3(2e6, 0, 0)
    with assert_raises():
        bounded.step(Duration(1))
    assert_equal(bounded.bodies[1].position.z, Float32(0.15))


def test_fast_within_margin_and_initial_back_overlap() raises:
    var near = _world(0.1, 0.115, -30, 1)
    near.step(Duration(0.01))
    assert_almost_equal(near.bodies[1].position.z, 0.385, atol=1e-7)
    assert_equal(near.contact_count, 1)
    for velocity in [Float32(-30), Float32(30), Float32(0)]:
        var back = _world(0.1, -0.05, velocity)
        back.step(Duration(0.01))
        assert_almost_equal(
            back.bodies[1].position.z, -0.05 + velocity * 0.01, atol=1e-7
        )
        assert_equal(back.contact_count, 0)


def test_late_friction_spin_pose_reference() raises:
    var world = _world(0.1, 0.4, -30)
    world.bodies[0].material = PhysicsMaterial(1, 0)
    world.bodies[1].material = PhysicsMaterial(1, 0)
    world.bodies[1].linear_velocity.x = 7
    world.step(Duration(0.02))
    # I=.4*m*r*r, impulse=-vx/(1/m+r*r/I)=-2, omega_y=50.
    # Impact at .01s; only the remaining .01s turns the sphere.
    assert_almost_equal(world.bodies[1].linear_velocity.x, 5, atol=1e-6)
    assert_almost_equal(world.bodies[1].angular_velocity.y, 50, atol=1e-5)
    var expected = Quaternion(0, 0.25, 0, 1)
    expected.normalize()
    assert_almost_equal(world.bodies[1].rotation.y, expected.y, atol=1e-7)
    assert_almost_equal(world.bodies[1].rotation.w, expected.w, atol=1e-7)


def test_absolute_scale_and_rotation_boundaries() raises:
    for choice in range(9):
        var world = _world()
        if choice == 0:
            world.bodies[1].shape.radius = 0.00001
        elif choice == 1:
            world.bodies[1].shape.radius = 10001
        elif choice == 2:
            world.bodies[1].position.x = 1000001
        elif choice == 3:
            world._triangles[0].a.x = -1000001
        elif choice == 4:
            world.bodies[1].rotation = Quaternion(0, 0, 0, 0)
        elif choice == 5:
            world.bodies[1].shape_rotation = Quaternion(
                nan[DType.float32](), 0, 0, 1
            )
        elif choice == 6:
            world._triangles[0] = Triangle(
                Vector3(0, 0, 0), Vector3(1e-30, 0, 0), Vector3(0, 1e-30, 0)
            )
        elif choice == 7:
            world.bodies[1].rotation = Quaternion(0, 2, 0, 0)
        else:
            world.bodies[1].position.x = 10000
        with assert_raises():
            world.step(Duration(0.01))
    for radius in [Float32(0.0001), Float32(10000)]:
        var world = PhysicsWorld()
        world.collision_detection = SPHERE_MESH_CCD
        world.gravity = Vector3(0, 0, 0)
        _ = world.add_body(_ball(radius, radius, 0))
        world.step(Duration(0.01))
        assert_equal(world.bodies[0].position.z, radius)


# Independent 70-digit Decimal convex-distance oracle, random seed 292.
# Generated by review_oracle_fixtures.py; does not use the sweep quadratic.
# All input coordinates and radii are exactly rounded Float32 values.
def test_independent_decimal_toi_references() raises:
    # Reference 1
    var hit0 = _sweep_triangle(
        _wide(
            Vector3(-6.404607772827148, 6.962575435638428, 4.217011451721191)
        ),
        _wide(
            Vector3(22.480182647705078, 11.51826000213623, 11.37504768371582)
        ),
        2.2524120807647705,
        Triangle(
            Vector3(-6.0, -8.0, 2.0),
            Vector3(-3.0, 7.0, 7.0),
            Vector3(0.0, -4.0, -9.0),
        ),
    )
    assert_almost_equal(hit0.fraction, 0.0984988668292722, atol=1e-12)
    # Reference 2
    var hit1 = _sweep_triangle(
        _wide(
            Vector3(2.3446297645568848, -5.212430477142334, 8.140819549560547)
        ),
        _wide(
            Vector3(-19.453229904174805, 9.51339340209961, -19.452999114990234)
        ),
        2.5592219829559326,
        Triangle(
            Vector3(-3.0, -2.0, 4.0),
            Vector3(-5.0, 1.0, -2.0),
            Vector3(0.0, 0.0, 5.0),
        ),
    )
    assert_almost_equal(hit1.fraction, 0.1685106110256775, atol=1e-12)
    # Reference 3
    var hit2 = _sweep_triangle(
        _wide(Vector3(4.250922203063965, 6.797332286834717, 8.605527877807617)),
        _wide(
            Vector3(
                -1.6430530548095703, -10.995927810668945, -3.175041675567627
            )
        ),
        0.8833143711090088,
        Triangle(
            Vector3(0.0, -10.0, 0.0),
            Vector3(3.0, -9.0, 9.0),
            Vector3(2.0, 6.0, -6.0),
        ),
    )
    assert_almost_equal(hit2.fraction, 0.9994904308484792, atol=1e-12)
    # Reference 4
    var hit3 = _sweep_triangle(
        _wide(
            Vector3(-1.8259806632995605, 2.8133738040924072, 4.851693630218506)
        ),
        _wide(Vector3(23.566516876220703, -7.897166728973389, 2.5849449634552)),
        2.2706496715545654,
        Triangle(
            Vector3(-2.0, -2.0, 8.0),
            Vector3(10.0, -1.0, 7.0),
            Vector3(-9.0, -10.0, 6.0),
        ),
    )
    assert_almost_equal(hit3.fraction, 0.32616453463542283, atol=1e-12)
    # Reference 5
    var hit4 = _sweep_triangle(
        _wide(
            Vector3(-0.8333256840705872, -1.7134406566619873, 7.030795574188232)
        ),
        _wide(
            Vector3(1.3557087182998657, 18.761314392089844, -13.911840438842773)
        ),
        0.989538311958313,
        Triangle(
            Vector3(2.0, 0.0, -8.0),
            Vector3(1.0, 3.0, 8.0),
            Vector3(-9.0, 7.0, 9.0),
        ),
    )
    assert_almost_equal(hit4.fraction, 0.19419651895161755, atol=1e-12)
    # Reference 6
    var hit5 = _sweep_triangle(
        _wide(
            Vector3(-11.617247581481934, -10.005097389221191, 9.122775077819824)
        ),
        _wide(
            Vector3(13.263544082641602, 5.9566874504089355, -13.721588134765625)
        ),
        2.8848330974578857,
        Triangle(
            Vector3(-2.0, -7.0, -6.0),
            Vector3(-4.0, -6.0, 6.0),
            Vector3(-9.0, 4.0, -7.0),
        ),
    )
    assert_almost_equal(hit5.fraction, 0.411368323276932, atol=1e-12)
    # Reference 7
    var hit6 = _sweep_triangle(
        _wide(
            Vector3(-0.7781533002853394, 8.152371406555176, -10.983351707458496)
        ),
        _wide(
            Vector3(0.1308935284614563, -21.804128646850586, 3.2431304454803467)
        ),
        1.151248574256897,
        Triangle(
            Vector3(-1.0, 2.0, -10.0),
            Vector3(-1.0, 8.0, -2.0),
            Vector3(6.0, -8.0, -4.0),
        ),
    )
    assert_almost_equal(hit6.fraction, 0.22633551998189855, atol=1e-12)
    # Reference 8
    var hit7 = _sweep_triangle(
        _wide(
            Vector3(
                -0.33804574608802795, -0.9298469424247742, 4.6791157722473145
            )
        ),
        _wide(
            Vector3(-14.574555397033691, 14.4216890335083, -18.820985794067383)
        ),
        0.9240142107009888,
        Triangle(
            Vector3(1.0, 10.0, -3.0),
            Vector3(-9.0, -5.0, 5.0),
            Vector3(-8.0, 7.0, -4.0),
        ),
    )
    assert_almost_equal(hit7.fraction, 0.20026651430456513, atol=1e-12)
    # Reference 9
    var hit8 = _sweep_triangle(
        _wide(
            Vector3(2.6359505653381348, -6.224852085113525, 5.639354705810547)
        ),
        _wide(
            Vector3(
                -18.652769088745117, -10.842069625854492, -22.899728775024414
            )
        ),
        2.2489073276519775,
        Triangle(
            Vector3(-7.0, -10.0, -1.0),
            Vector3(10.0, 0.0, 0.0),
            Vector3(-9.0, 8.0, 9.0),
        ),
    )
    assert_almost_equal(hit8.fraction, 0.2085335136975226, atol=1e-12)
    # Reference 10
    var hit9 = _sweep_triangle(
        _wide(
            Vector3(-0.01935853622853756, 6.050907135009766, -1.755813479423523)
        ),
        _wide(
            Vector3(3.111069679260254, -10.964730262756348, -2.8700311183929443)
        ),
        2.503679037094116,
        Triangle(
            Vector3(1.0, -4.0, -8.0),
            Vector3(8.0, -1.0, -4.0),
            Vector3(8.0, 4.0, -6.0),
        ),
    )
    assert_almost_equal(hit9.fraction, 0.8786370292915809, atol=1e-12)
    # Reference 11
    var hit10 = _sweep_triangle(
        _wide(
            Vector3(-11.280491828918457, -4.95033073425293, -3.0438387393951416)
        ),
        _wide(Vector3(0.537691593170166, 13.149368286132812, -6.6351318359375)),
        1.336260437965393,
        Triangle(
            Vector3(9.0, 0.0, -4.0),
            Vector3(-4.0, 2.0, 3.0),
            Vector3(-10.0, 3.0, -7.0),
        ),
    )
    assert_almost_equal(hit10.fraction, 0.5420050631190904, atol=1e-12)
    # Reference 12
    var hit11 = _sweep_triangle(
        _wide(
            Vector3(-3.0109753608703613, 5.325314998626709, -0.583259105682373)
        ),
        _wide(
            Vector3(-8.36039924621582, -7.240940570831299, -7.745724678039551)
        ),
        2.73030161857605,
        Triangle(
            Vector3(-10.0, 2.0, 0.0),
            Vector3(6.0, -9.0, -1.0),
            Vector3(-9.0, 2.0, -5.0),
        ),
    )
    assert_almost_equal(hit11.fraction, 0.33673320455588807, atol=1e-12)
    # Reference 13
    var hit12 = _sweep_triangle(
        _wide(Vector3(3.0624241828918457, -4.096953392028809, -8.9560546875)),
        _wide(
            Vector3(-8.934106826782227, 12.027965545654297, 23.28369903564453)
        ),
        1.7259094715118408,
        Triangle(
            Vector3(0.0, -6.0, 2.0),
            Vector3(-3.0, 1.0, 10.0),
            Vector3(-1.0, 8.0, 6.0),
        ),
    )
    assert_almost_equal(hit12.fraction, 0.5015862753261436, atol=1e-12)
    # Reference 14
    var hit13 = _sweep_triangle(
        _wide(
            Vector3(8.119400978088379, -9.586431503295898, 11.006877899169922)
        ),
        _wide(
            Vector3(
                -23.110488891601562, 21.672250747680664, -22.922107696533203
            )
        ),
        2.1579906940460205,
        Triangle(
            Vector3(-10.0, -4.0, 10.0),
            Vector3(5.0, -4.0, -2.0),
            Vector3(1.0, -3.0, 4.0),
        ),
    )
    assert_almost_equal(hit13.fraction, 0.2508097407574668, atol=1e-12)
    # Reference 15
    var hit14 = _sweep_triangle(
        _wide(
            Vector3(-3.3106558322906494, 4.898774147033691, 8.568717956542969)
        ),
        _wide(
            Vector3(23.175031661987305, -19.5069522857666, 6.949391841888428)
        ),
        2.1282496452331543,
        Triangle(
            Vector3(8.0, 7.0, -2.0),
            Vector3(2.0, 9.0, -3.0),
            Vector3(-1.0, 2.0, 9.0),
        ),
    )
    assert_almost_equal(hit14.fraction, 0.049152827360240216, atol=1e-12)
    # Reference 16
    var hit15 = _sweep_triangle(
        _wide(
            Vector3(8.532869338989258, 7.855955600738525, -9.626120567321777)
        ),
        _wide(
            Vector3(-20.258302688598633, -18.370670318603516, 14.65903377532959)
        ),
        0.47903013229370117,
        Triangle(
            Vector3(-9.0, 5.0, -4.0),
            Vector3(-7.0, 7.0, 5.0),
            Vector3(1.0, -5.0, -5.0),
        ),
    )
    assert_almost_equal(hit15.fraction, 0.484519945261672, atol=1e-12)
    # Reference 17
    var hit16 = _sweep_triangle(
        _wide(
            Vector3(
                -5.202511310577393, -7.8339080810546875, -1.6072343587875366
            )
        ),
        _wide(
            Vector3(24.654693603515625, 21.87177276611328, 5.2721147537231445)
        ),
        2.2912216186523438,
        Triangle(
            Vector3(10.0, -9.0, -2.0),
            Vector3(2.0, 6.0, 9.0),
            Vector3(-8.0, 6.0, -7.0),
        ),
    )
    assert_almost_equal(hit16.fraction, 0.2499778397133942, atol=1e-12)
    # Reference 18
    var hit17 = _sweep_triangle(
        _wide(
            Vector3(1.9682714939117432, 8.932855606079102, 1.6718260049819946)
        ),
        _wide(
            Vector3(-11.08929443359375, -19.190547943115234, 4.937033176422119)
        ),
        0.8652935028076172,
        Triangle(
            Vector3(8.0, -2.0, 9.0),
            Vector3(5.0, -3.0, 4.0),
            Vector3(-6.0, 5.0, 0.0),
        ),
    )
    assert_almost_equal(hit17.fraction, 0.28169141227081024, atol=1e-12)
    # Reference 19
    var hit18 = _sweep_triangle(
        _wide(
            Vector3(-5.629693984985352, 3.514653444290161, 1.2990964651107788)
        ),
        _wide(
            Vector3(4.514185428619385, -15.921133041381836, 5.6743364334106445)
        ),
        0.2594442367553711,
        Triangle(
            Vector3(-3.0, -9.0, 2.0),
            Vector3(-5.0, 6.0, 7.0),
            Vector3(10.0, -8.0, -1.0),
        ),
    )
    assert_almost_equal(hit18.fraction, 0.4174599051000431, atol=1e-12)
    # Reference 20
    var hit19 = _sweep_triangle(
        _wide(
            Vector3(7.908079147338867, 11.756706237792969, 7.746488094329834)
        ),
        _wide(
            Vector3(-12.408896446228027, -22.72400665283203, -15.55921745300293)
        ),
        1.7455371618270874,
        Triangle(
            Vector3(-2.0, -5.0, 5.0),
            Vector3(9.0, 9.0, -2.0),
            Vector3(-9.0, -5.0, 1.0),
        ),
    )
    assert_almost_equal(hit19.fraction, 0.346105140378399, atol=1e-12)
    # Reference 21
    var hit20 = _sweep_triangle(
        _wide(
            Vector3(-7.3976826667785645, 4.868844509124756, 11.804160118103027)
        ),
        _wide(
            Vector3(6.157536029815674, -16.339202880859375, -19.692514419555664)
        ),
        2.8184149265289307,
        Triangle(
            Vector3(6.0, 10.0, 0.0),
            Vector3(-5.0, -3.0, -6.0),
            Vector3(-3.0, -5.0, 1.0),
        ),
    )
    assert_almost_equal(hit20.fraction, 0.4737320981668573, atol=1e-12)
    # Reference 22
    var hit21 = _sweep_triangle(
        _wide(Vector3(-4.93776273727417, 1.462788462638855, 10.66417407989502)),
        _wide(
            Vector3(23.461509704589844, 17.74720001220703, -22.865074157714844)
        ),
        1.5122257471084595,
        Triangle(
            Vector3(3.0, 4.0, 9.0),
            Vector3(-8.0, 6.0, 3.0),
            Vector3(-4.0, 2.0, 7.0),
        ),
    )
    assert_almost_equal(hit21.fraction, 0.08299354879910914, atol=1e-12)
    # Reference 23
    var hit22 = _sweep_triangle(
        _wide(
            Vector3(2.924332618713379, 0.2572369873523712, 6.190299987792969)
        ),
        _wide(
            Vector3(14.95781135559082, -17.58538818359375, -15.629447937011719)
        ),
        0.7574595808982849,
        Triangle(
            Vector3(10.0, -4.0, 9.0),
            Vector3(9.0, 5.0, 8.0),
            Vector3(3.0, 0.0, 3.0),
        ),
    )
    assert_almost_equal(hit22.fraction, 0.0809880494122789, atol=1e-12)


def test_rollback_preserves_dirty_raycast_tie() raises:
    var world = _world(0.1, 0.5, -300, 1)
    _ = world.add_body(_floor())
    _ = world.add_body(_floor(1, True))
    world.ccd_max_impacts = 1
    var before = world.raycast(
        Vector3(10, 0, 0.5), Vector3(0, 0, -1), Length(1), BodyId(-1)
    ).value()
    assert_equal(before.body.value, 0)
    with assert_raises():
        world.step(Duration(0.01))
    var after = world.raycast(
        Vector3(10, 0, 0.5), Vector3(0, 0, -1), Length(1), BodyId(-1)
    ).value()
    assert_equal(after.body, before.body)
    assert_equal(after.distance, before.distance)
    assert_true(world._dirty)
    var empty = PhysicsWorld()
    empty.collision_detection = SPHERE_MESH_CCD
    empty.ccd_max_impacts = 0
    with assert_raises():
        empty.step(Duration(0.01))
    var rays = _world(0.1, -2, 0)
    rays.step(Duration(0.01))
    var hit = rays.raycast(
        Vector3(0, 0, 10), Vector3(0, 0, -1), Length(100), BodyId(-1)
    ).value()
    assert_equal(hit.body.value, 0)
    assert_false(
        rays.raycast(
            Vector3(200, 200, 10), Vector3(0, 0, 1), Length(100), BodyId(-1)
        )
    )


def test_ill_conditioned_triangle_is_refused() raises:
    var world = _world()
    world._triangles[0] = Triangle(
        Vector3(-1e4, -1e4, 0),
        Vector3(1e4, 1e4, 1e-20),
        Vector3(0, 1e-20, 1e-20),
    )
    with assert_raises():
        world.step(Duration(0.01))
    assert_equal(world.bodies[1].position.z, Float32(0.15))


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite^.run()
