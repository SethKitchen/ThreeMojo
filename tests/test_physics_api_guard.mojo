# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public value accessors and state-entry validation guard body mass state."""

from extensions.physics.body import (
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.physics.shape import Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from tests.test_physics_modes import (
    _body,
    _effective_state_equal,
    _vector_equal,
)
from units.si import Duration, Mass, SECOND


def test_accessors_return_independent_values() raises:
    var body = _body()
    var before = body.copy()
    var mode = body.kind()
    mode.value = 42
    assert_equal(mode.value, 42)
    var inverse = body.inverse_inertia()
    for i in range(9):
        inverse.elements[i] = 0
    assert_equal(inverse.elements[0], 0)
    _effective_state_equal(body, before)
    var copied = body.copy()
    copied.set_kind(KINEMATIC)
    copied.set_kind(DYNAMIC)
    copied.set_mass(Mass(12))
    _effective_state_equal(body, before)
    assert_equal(copied.mass(), 12)
    assert_equal(copied.inverse_mass(), Float32(1.0 / 12.0))


def test_custom_inverse_updates_are_atomic_and_exact() raises:
    var body = _body()
    var before = body.copy()
    for index in range(9):
        for value in [nan[DType.float32](), inf[DType.float32]()]:
            var inverse = body.inverse_inertia()
            inverse.elements[index] = value
            with assert_raises():
                body.set_inverse_inertia(inverse)
            _effective_state_equal(body, before)
    var custom = Matrix3()
    # The custom-constraint API preserves finite entries; the physical
    # positive-definite tensor contract belongs to set_inertia instead.
    custom.elements[0] = 0
    custom.elements[1] = 0.25
    custom.elements[3] = 0.25
    # Preserve the prior custom-write contract, including nonphysical
    # negative and nonsymmetric controls. validate is not a PSD solver.
    custom.elements[4] = -2
    custom.elements[2] = 0.75
    custom.elements[6] = -0.125
    body.set_inverse_inertia(custom)
    body.validate()
    body.set_kind(STATIC)
    with assert_raises():
        body.set_inverse_inertia(Matrix3())
    body.set_kind(DYNAMIC)
    for i in range(9):
        assert_equal(body.inverse_inertia().elements[i], custom.elements[i])


def test_unsupported_internal_edits_fail_before_world_mutation() raises:
    for index in range(14):
        var body = _body()
        body.set_kind(KINEMATIC)
        if index == 0:
            body._kind = BodyKind(10)
        elif index == 1:
            body._kind = DYNAMIC
        elif index == 2:
            body._mass = 2
        elif index == 3:
            body._inverse_mass = 2
        elif index == 4:
            body._dynamic_mass = 0
        else:
            body._inverse_inertia.elements[index - 5] = 1
        var world = PhysicsWorld()
        with assert_raises():
            _ = world.add_body(body.copy())
        assert_equal(world.body_count(), 0)
        assert_equal(len(world._order), 0)
        assert_equal(len(world._triangles), 0)
        var before = body.copy()
        with assert_raises():
            body.apply_impulse(Vector3(1, 2, 3), Vector3(4, 5, 6))
        _effective_state_equal(body, before)
        # Public lists are also mutable in Mojo: validate the whole batch
        # before integrating even its first valid body or clearing forces.
        var valid = _body()
        valid.add_force(Vector3(6, 0, 0), Vector3(0, 0, 0))
        var original = valid.copy()
        _ = world.add_body(valid^)
        world.bodies.append(body^)
        with assert_raises():
            world.step(Duration(0.1, SECOND))
        _effective_state_equal(world.bodies[0], original)
        assert_equal(world.contact_count, 0)
        assert_equal(len(world.events), 0)


def test_mesh_kind_tampering_is_rejected() raises:
    var body = RigidBody(
        STATIC,
        Shape.mesh(
            [Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))]
        ),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.validate()
    for mode in [DYNAMIC, KINEMATIC]:
        body._kind = mode
        with assert_raises():
            body.validate()
        var world = PhysicsWorld()
        with assert_raises():
            _ = world.add_body(body.copy())
        assert_equal(world.body_count(), 0)
        assert_equal(len(world._triangles), 0)
        assert_equal(world._dirty, False)


def test_same_mode_cannot_skip_state_validation() raises:
    var body = _body()
    body._inverse_mass = 1
    var before = body.copy()
    with assert_raises():
        body.set_kind(DYNAMIC)
    _effective_state_equal(body, before)
    with assert_raises():
        body.set_mass(Mass(8))
    with assert_raises():
        body.set_inertia(Matrix3())
    with assert_raises():
        body.set_inverse_inertia(Matrix3())
    with assert_raises():
        body.set_shape_pose(Vector3(0, 0, 0), Quaternion.identity())
    with assert_raises():
        body.set_center_of_mass(Vector3(0, 0, 0))
    _effective_state_equal(body, before)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
