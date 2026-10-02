# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared body mode changes preserve configured mass and contact response."""

from extensions.physics.body import (
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, Mass, SECOND


def _body() raises -> RigidBody:
    return RigidBody(
        DYNAMIC,
        Shape.box(Length(1), Length(2), Length(3)),
        Mass(6),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _tensor() -> Matrix3:
    var out = Matrix3()
    out.elements[0] = 2
    out.elements[4] = 4
    out.elements[8] = 8
    return out


def _vector_equal(a: Vector3, b: Vector3) raises:
    assert_equal(a.x, b.x)
    assert_equal(a.y, b.y)
    assert_equal(a.z, b.z)


def _zero_mass(body: RigidBody) raises:
    assert_equal(body.mass, 0)
    assert_equal(body.inverse_mass, 0)
    var world = body.world_inverse_inertia()
    for i in range(9):
        assert_equal(body.inverse_inertia.elements[i], 0)
        assert_equal(world.elements[i], 0)


def test_mode_chain_keeps_dynamic_configuration() raises:
    var body = _body()
    body.set_shape_pose(
        Vector3(0.7, 0.8, 0.9),
        Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(30, DEGREE)),
    )
    var shape_rotation = body.shape_rotation
    var configured = _tensor()
    configured.elements[1] = 0.5
    configured.elements[3] = 0.5
    configured.elements[2] = 0.25
    configured.elements[6] = 0.25
    configured.elements[5] = 0.75
    configured.elements[7] = 0.75
    body.set_inertia(configured)
    body.set_center_of_mass(Vector3(0.2, 0.3, 0.4))
    var local = body.inverse_inertia
    body.linear_velocity = Vector3(3, 2, 1)
    body.angular_velocity = Vector3(1, 2, 3)
    body.set_kind(KINEMATIC)
    _zero_mass(body)
    _vector_equal(body.linear_velocity, Vector3(3, 2, 1))
    _vector_equal(body.angular_velocity, Vector3(1, 2, 3))
    body.apply_impulse(Vector3(100, 200, 300), Vector3(1, 2, 3))
    _vector_equal(body.linear_velocity, Vector3(3, 2, 1))
    _vector_equal(body.angular_velocity, Vector3(1, 2, 3))
    body.set_kind(KINEMATIC)
    body.push_velocity = Vector3(4, 5, 6)
    body.push_angular = Vector3(7, 8, 9)
    body.set_kind(STATIC)
    _zero_mass(body)
    _vector_equal(body.push_velocity, Vector3(0, 0, 0))
    _vector_equal(body.push_angular, Vector3(0, 0, 0))
    _vector_equal(body.linear_velocity, Vector3(0, 0, 0))
    _vector_equal(body.angular_velocity, Vector3(0, 0, 0))
    body.set_kind(DYNAMIC)
    assert_equal(body.mass, 6)
    assert_equal(body.inverse_mass, Float32(1.0 / 6.0))
    _vector_equal(body.center_of_mass, Vector3(0.2, 0.3, 0.4))
    _vector_equal(body.shape_position, Vector3(0.7, 0.8, 0.9))
    assert_equal(body.shape_rotation.x, shape_rotation.x)
    assert_equal(body.shape_rotation.y, shape_rotation.y)
    assert_equal(body.shape_rotation.z, shape_rotation.z)
    assert_equal(body.shape_rotation.w, shape_rotation.w)
    for i in range(9):
        assert_equal(body.inverse_inertia.elements[i], local.elements[i])
    body.apply_impulse(Vector3(6, 0, 0), body.world_center_of_mass())
    _vector_equal(body.linear_velocity, Vector3(1, 0, 0))
    body.set_kind(DYNAMIC)
    _vector_equal(body.linear_velocity, Vector3(1, 0, 0))


def test_restored_tensor_uses_the_new_world_orientation() raises:
    var body = _body()
    body.set_inertia(_tensor())
    body.set_kind(KINEMATIC)
    body.rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(90, DEGREE)
    )
    body.position = Vector3(10, 20, 30)
    body.set_kind(DYNAMIC)
    var tensor = body.world_inverse_inertia()
    assert_almost_equal(tensor.elements[0], 0.25, atol=1e-6)
    assert_almost_equal(tensor.elements[4], 0.5, atol=1e-6)
    assert_almost_equal(tensor.elements[8], 0.125, atol=1e-6)
    assert_almost_equal(tensor.elements[1], 0, atol=1e-6)
    _vector_equal(body.position, Vector3(10, 20, 30))
    assert_equal(body.inverse_inertia.elements[0], 0.5)
    assert_equal(body.inverse_inertia.elements[4], 0.25)


def test_repeated_toggles_keep_locked_axes() raises:
    var body = _body()
    for i in range(9):
        body.inverse_inertia.elements[i] = 0
    for _ in range(4):
        body.set_kind(KINEMATIC)
        _zero_mass(body)
        body.set_kind(DYNAMIC)
        assert_equal(body.mass, 6)
        for i in range(9):
            assert_equal(body.inverse_inertia.elements[i], 0)
    body.apply_impulse(Vector3(6, 0, 0), Vector3(0, 1, 0))
    _vector_equal(body.linear_velocity, Vector3(1, 0, 0))
    _vector_equal(body.angular_velocity, Vector3(0, 0, 0))


def test_disabled_configuration_edits_are_refused() raises:
    var body = _body()
    body.set_inertia(_tensor())
    body.set_kind(KINEMATIC)
    with assert_raises():
        body.set_mass(Mass(10))
    with assert_raises():
        body.set_inertia(Matrix3())
    with assert_raises():
        body.set_shape_pose(Vector3(1, 0, 0), Quaternion.identity())
    with assert_raises():
        body.set_center_of_mass(Vector3(1, 0, 0))
    _zero_mass(body)
    _vector_equal(body.shape_position, Vector3(0, 0, 0))
    _vector_equal(body.center_of_mass, Vector3(0, 0, 0))
    body.set_kind(DYNAMIC)
    assert_equal(body.mass, 6)
    assert_equal(body.inverse_inertia.elements[0], 0.5)
    body.set_mass(Mass(12))
    var tensor = body.inverse_inertia
    body.set_kind(STATIC)
    body.set_kind(KINEMATIC)
    body.set_kind(DYNAMIC)
    assert_equal(body.mass, 12)
    for i in range(9):
        assert_equal(body.inverse_inertia.elements[i], tensor.elements[i])


def test_invalid_transitions_leave_state_unchanged() raises:
    var body = _body()
    with assert_raises():
        body.set_kind(BodyKind(3))
    assert_equal(body.kind, DYNAMIC)
    assert_equal(body.mass, 6)
    var still = RigidBody(
        STATIC,
        Shape.sphere(Length(1)),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    with assert_raises():
        still.set_kind(DYNAMIC)
    assert_equal(still.kind, STATIC)
    _zero_mass(still)
    still.set_kind(KINEMATIC)
    with assert_raises():
        still.set_kind(DYNAMIC)
    _zero_mass(still)
    var mesh = RigidBody(
        STATIC,
        Shape.mesh(
            [Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))]
        ),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    for kind in [DYNAMIC, KINEMATIC]:
        with assert_raises():
            mesh.set_kind(kind)
    mesh.set_kind(STATIC)
    assert_equal(mesh.kind, STATIC)


def test_nonfinite_mass_state_is_not_saved() raises:
    for bad in [
        Float32(0),
        Float32(-1),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        var body = _body()
        body.mass = bad
        with assert_raises():
            body.set_kind(KINEMATIC)
        assert_equal(body.kind, DYNAMIC)
    var body = _body()
    body.inverse_mass = 0.5
    with assert_raises():
        body.set_kind(KINEMATIC)
    assert_equal(body.mass, 6)
    body.inverse_mass = 1 / body.mass
    body.inverse_inertia.elements[4] = nan[DType.float32]()
    with assert_raises():
        body.set_kind(STATIC)
    assert_equal(body.kind, DYNAMIC)
    assert_equal(body.mass, 6)


def _effective_state_equal(body: RigidBody, before: RigidBody) raises:
    assert_equal(body.kind, before.kind)
    assert_equal(body.mass, before.mass)
    assert_equal(body.inverse_mass, before.inverse_mass)
    for i in range(9):
        assert_equal(
            body.inverse_inertia.elements[i], before.inverse_inertia.elements[i]
        )
    _vector_equal(body.center_of_mass, before.center_of_mass)
    _vector_equal(body.position, before.position)
    _vector_equal(body.linear_velocity, before.linear_velocity)
    _vector_equal(body.angular_velocity, before.angular_velocity)
    _vector_equal(body.push_velocity, before.push_velocity)
    _vector_equal(body.push_angular, before.push_angular)
    _vector_equal(body.force, before.force)
    _vector_equal(body.torque, before.torque)


def test_invalid_retained_state_is_rejected_atomically() raises:
    for index in range(9):
        var body = _body()
        body.set_kind(KINEMATIC)
        body.linear_velocity = Vector3(1, 2, 3)
        body.angular_velocity = Vector3(4, 5, 6)
        body.push_velocity = Vector3(7, 8, 9)
        body.push_angular = Vector3(10, 11, 12)
        body.add_force(Vector3(13, 14, 15), Vector3(1, 2, 3))
        var before = body.copy()
        if index == 0:
            body._dynamic_mass = 0
        elif index == 1:
            body._dynamic_mass = -1
        elif index == 2:
            body._dynamic_mass = inf[DType.float32]()
        elif index == 3:
            body._dynamic_mass = nan[DType.float32]()
        elif index == 4:
            body._dynamic_inverse_mass = 0
        elif index == 5:
            body._dynamic_inverse_mass = -1
        elif index == 6:
            body._dynamic_inverse_mass = inf[DType.float32]()
        elif index == 7:
            body._dynamic_inverse_mass = nan[DType.float32]()
        else:
            body._dynamic_inverse_mass = 0.5
        with assert_raises():
            body.set_kind(DYNAMIC)
        _effective_state_equal(body, before)
    for index in range(9):
        var body = _body()
        body.set_kind(STATIC)
        var before = body.copy()
        body._dynamic_inverse_inertia.elements[index] = nan[DType.float32]()
        with assert_raises():
            body.set_kind(DYNAMIC)
        _effective_state_equal(body, before)


def test_one_locked_axis_keeps_the_other_axis_response() raises:
    var body = _body()
    body.set_inertia(_tensor())
    body.inverse_inertia.elements[0] = 0
    for _ in range(4):
        body.set_kind(KINEMATIC)
        _zero_mass(body)
        body.set_kind(DYNAMIC)
        assert_equal(body.inverse_inertia.elements[0], 0)
        assert_equal(body.inverse_inertia.elements[4], 0.25)
        assert_equal(body.inverse_inertia.elements[8], 0.125)
    body.apply_impulse(Vector3(0, 6, 0), Vector3(0, 0, 1))
    _vector_equal(body.angular_velocity, Vector3(0, 0, 0))
    body.apply_impulse(Vector3(6, 0, 0), Vector3(0, 1, 0))
    _vector_equal(body.angular_velocity, Vector3(0, 0, -0.75))


def test_force_lifetime_is_one_world_step_across_modes() raises:
    for restore_before_step in [False, True]:
        var world = PhysicsWorld()
        world.gravity = Vector3(0, 0, 0)
        var body = _body()
        body.set_inertia(_tensor())
        body.add_force(Vector3(6, 0, 0), Vector3(0, 1, 0))
        body.set_kind(KINEMATIC)
        body.set_kind(STATIC)
        body.set_kind(KINEMATIC)
        _vector_equal(body.force, Vector3(6, 0, 0))
        _vector_equal(body.torque, Vector3(0, 0, -6))
        if restore_before_step:
            body.set_kind(DYNAMIC)
        _ = world.add_body(body^)
        world.step(Duration(1, SECOND))
        _vector_equal(world.bodies[0].force, Vector3(0, 0, 0))
        _vector_equal(world.bodies[0].torque, Vector3(0, 0, 0))
        if restore_before_step:
            _vector_equal(world.bodies[0].linear_velocity, Vector3(1, 0, 0))
            _vector_equal(
                world.bodies[0].angular_velocity, Vector3(0, 0, -0.75)
            )
        else:
            _vector_equal(world.bodies[0].linear_velocity, Vector3(0, 0, 0))
            _vector_equal(world.bodies[0].angular_velocity, Vector3(0, 0, 0))
            world.bodies[0].set_kind(DYNAMIC)
            world.step(Duration(1, SECOND))
            _vector_equal(world.bodies[0].linear_velocity, Vector3(0, 0, 0))
            _vector_equal(world.bodies[0].angular_velocity, Vector3(0, 0, 0))


def test_native_disabled_bodies_keep_shape_edit_compatibility() raises:
    var body = RigidBody(
        KINEMATIC,
        Shape.sphere(Length(1)),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.set_shape_pose(Vector3(1, 2, 3), Quaternion.identity())
    body.set_center_of_mass(Vector3(4, 5, 6))
    body.set_kind(STATIC)
    body.set_kind(STATIC)
    _vector_equal(body.shape_position, Vector3(1, 2, 3))
    _vector_equal(body.center_of_mass, Vector3(4, 5, 6))
    _zero_mass(body)


def _contact_world(convert: Bool) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.bounce_threshold = 0
    var moving = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(1)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    moving.linear_velocity = Vector3(2, 0, 0)
    moving.material = PhysicsMaterial(0, 1)
    _ = world.add_body(moving^)
    var fixed = RigidBody(
        DYNAMIC if convert else KINEMATIC,
        Shape.sphere(Length(1)),
        Mass(7),
        Vector3(1.9, 0, 0),
        Quaternion.identity(),
    )
    fixed.material = PhysicsMaterial(0, 1)
    if convert:
        fixed.set_kind(KINEMATIC)
    _ = world.add_body(fixed^)
    return world^


def test_kinematic_contact_matches_an_infinite_mass_reference() raises:
    var converted = _contact_world(True)
    var reference = _contact_world(False)
    converted.step(Duration(0.01, SECOND))
    reference.step(Duration(0.01, SECOND))
    assert_true(converted.contact_count > 0)
    assert_almost_equal(
        converted.bodies[0].linear_velocity.x,
        reference.bodies[0].linear_velocity.x,
        atol=1e-6,
    )
    assert_true(converted.bodies[0].linear_velocity.x < 0)
    _vector_equal(converted.bodies[1].linear_velocity, Vector3(0, 0, 0))
    _vector_equal(converted.bodies[1].position, Vector3(1.9, 0, 0))
    _zero_mass(converted.bodies[1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
