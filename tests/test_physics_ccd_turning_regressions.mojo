# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent controls for turning CCD progress, ordering and rebound reach."""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD, _turning_step
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Length, Mass, Duration


def _v(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def _mesh(t: Triangle, bounce: Float32 = 0) raises -> RigidBody:
    var body = RigidBody(
        STATIC,
        Shape.mesh([t]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _world(brute: Bool = False) -> PhysicsWorld:
    var out = PhysicsWorld()
    out.gravity = Vector3(0, 0, 0)
    out.collision_detection = SPHERE_MESH_CCD
    out._ccd_brute_force = brute
    return out^


def _capsule(z: Float32) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(0.1), Length(0.4)),
        Mass(1),
        Vector3(0, 0, z),
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0, 0)
    body.linear_velocity = Vector3(0, 0, -30)
    return body^


def _index_fillers(mut world: PhysicsWorld) raises:
    # Nine triangles force the indexed path. These seven are out of reach.
    for k in range(7):
        var x = Float32(100 + k * 3)
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(x, -1, 0),
                    Vector3(x + 1, -1, 0),
                    Vector3(x, 1, 0),
                )
            )
        )


def test_a_small_curvature_keeps_the_closing_root() raises:
    var floor = Triangle(
        Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(0, 10, 0)
    )
    # The zero-curvature limit is distance / closing speed. Directly
    # adding the quadratic root to -30 loses every significant digit.
    for curvature in [Float64(0), Float64(4e-17), Float64(4e-25)]:
        var time = _turning_step(
            (_v(0, 0, 0.6), _v(0, 0, 1.4)),
            (_v(0, 0, -30), _v(0, 0, -30)),
            0.1,
            0.1 / 1024,
            curvature,
            floor,
        )
        assert_almost_equal(time, (0.5 + 0.1 / 1024) / 30, atol=1e-12)
        assert_true(time > 0.01)


def test_a_slowly_turning_capsule_can_translate() raises:
    # No collision occurs in this interval. A vanishing spin must not
    # change a clear 0.3 m translation into a sub-step-budget failure.
    for spin in [Float32(0), Float32(1e-12), Float32(-1e-8), Float32(1e-4)]:
        var world = _world()
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(-10, -10, 0),
                    Vector3(10, -10, 0),
                    Vector3(0, 10, 0),
                )
            )
        )
        var body = _capsule(1)
        body.angular_velocity = Vector3(spin, 0, 0)
        _ = world.add_body(body^)
        world.step(Duration(0.01))
        assert_almost_equal(world.bodies[1].position.z, 0.7, atol=1e-6)
        assert_equal(world.bodies[1].linear_velocity.z, -30)
        assert_equal(world.contact_count, 0)


def test_turning_triangle_ties_keep_insertion_order() raises:
    # Both triangles share a plane and cover the first contact. The
    # second sorts first spatially, but its elastic material must not win
    # over the first triangle's plastic material at the same instant.
    for brute in [False, True]:
        var world = _world(brute)
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(-1, -10, 0),
                    Vector3(21, -10, 0),
                    Vector3(-1, 10, 0),
                )
            )
        )
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(-21, -10, 0),
                    Vector3(1, -10, 0),
                    Vector3(1, 10, 0),
                ),
                1,
            )
        )
        _index_fillers(world)
        _ = world.add_body(_capsule(0.8))
        world.step(Duration(0.02))
        assert_equal(world.contact_count, 1)
        assert_almost_equal(world.bodies[9].linear_velocity.z, 0, atol=1e-5)
        assert_almost_equal(world.bodies[9].position.z, 0.5, atol=0.00011)
        assert_equal(len(world.events), 2)
        assert_equal(world.events[0].body.value, 9)
        assert_equal(world.events[0].other.value, 0)
        assert_equal(world.events[1].body.value, 0)
        assert_equal(world.events[1].other.value, 9)
        assert_true(
            world.events[0].normal_impulse == -world.events[1].normal_impulse
        )


def test_an_impulse_refreshes_the_turning_candidate_reach() raises:
    # An offset sphere spins into the upper wall. Its high inertia lets
    # the bounce turn spin into almost 2 m/s of translation. The lower
    # wall lies outside the original 6.12 m candidate radius, but the
    # sphere reaches it before this step ends.
    var positions = List[Vector3]()
    var velocities = List[Vector3]()
    var spins = List[Vector3]()
    for brute in [False, True]:
        var world = _world(brute)
        world.bounce_threshold = 0.001
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(-2, 0.2, -2),
                    Vector3(2, 0.2, -2),
                    Vector3(0, 0.2, 2),
                ),
                1,
            )
        )
        _ = world.add_body(
            _mesh(
                Triangle(
                    Vector3(-2, -7, -2),
                    Vector3(0, -7, 2),
                    Vector3(2, -7, -2),
                ),
                1,
            )
        )
        _index_fillers(world)
        var body = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.1)),
            Mass(1),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
        body.set_shape_pose(Vector3(1, 0, 0), Quaternion.identity())
        body.set_center_of_mass(Vector3(0, 0, 0))
        var inverse = Matrix3()
        inverse.elements[0] = 0.001
        inverse.elements[4] = 0.001
        inverse.elements[8] = 0.001
        body.set_inverse_inertia(inverse)
        body.angular_velocity = Vector3(0, 0, 1)
        body.material = PhysicsMaterial(0, 1)
        _ = world.add_body(body^)
        world.step(Duration(5))
        assert_true(world.bodies[9].shape_world_position().y > -6.901)
        assert_equal(world.contact_count, 2)
        assert_equal(len(world.events), 4)
        assert_equal(world.events[0].body.value, 9)
        assert_equal(world.events[0].other.value, 0)
        assert_equal(world.events[2].body.value, 9)
        assert_equal(world.events[2].other.value, 1)
        positions.append(world.bodies[9].position)
        velocities.append(world.bodies[9].linear_velocity)
        spins.append(world.bodies[9].angular_velocity)
    assert_true(positions[0] == positions[1])
    assert_true(velocities[0] == velocities[1])
    assert_true(spins[0] == spins[1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
