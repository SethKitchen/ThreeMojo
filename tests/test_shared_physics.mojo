# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared mechanics, legacy type identity and an anatomy tensor handoff."""

from extensions.carla.physics.body import BodyId as CarlaBodyId
from extensions.carla.physics.body import RigidBody as CarlaRigidBody
from extensions.carla.physics.quantities import Torque as CarlaTorque
from extensions.carla.physics.shape import Shape as CarlaShape
from extensions.carla.physics.world import PhysicsWorld as CarlaPhysicsWorld
from extensions.humanoid.skeleton.limb.inertia import SegmentInertia
from extensions.physics.body import BodyId, DYNAMIC, RigidBody
from extensions.physics.quantities import NEWTON_METER, Torque
from extensions.physics.shape import Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.testing import TestSuite, assert_almost_equal, assert_equal
from units.si import Duration, Length, Mass, MomentOfInertia, SECOND


def _legacy_world(
    mut world: CarlaPhysicsWorld, var body: CarlaRigidBody
) raises -> CarlaBodyId:
    return world.add_body(body^)


def test_legacy_imports_share_types() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var shape: CarlaShape = Shape.sphere(Length(1))
    var body = RigidBody(
        DYNAMIC, shape^, Mass(2), Vector3(0, 0, 0), Quaternion.identity()
    )
    var id: BodyId = _legacy_world(world, body^)
    var torque: Torque = CarlaTorque(3, NEWTON_METER)
    assert_equal(id.value, 0)
    assert_equal(torque.value, 3)


def test_y_up_world_accepts_an_external_force() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, -10, 0)
    var id = world.add_body(
        RigidBody(
            DYNAMIC,
            Shape.sphere(Length(1)),
            Mass(2),
            Vector3(0, 10, 0),
            Quaternion.identity(),
        )
    )
    # A 20 N upward force cancels this body's weight without a CARLA actor.
    world.bodies[id.value].add_force(Vector3(0, 20, 0), Vector3(0, 10, 0))
    world.step(Duration(0.1, SECOND))
    assert_almost_equal(world.bodies[id.value].position.y, 10, atol=1e-6)
    world.step(Duration(0.1, SECOND))
    assert_almost_equal(world.bodies[id.value].linear_velocity.y, -1, atol=1e-6)
    assert_almost_equal(world.bodies[id.value].position.y, 9.9, atol=1e-6)


def test_anatomy_tensor_keeps_its_off_diagonal_terms() raises:
    # An authored anatomy result, not a visual mesh's uniform density.
    var segment = SegmentInertia(
        Mass(2),
        Vector3(1, 2, 3),
        MomentOfInertia(2),
        MomentOfInertia(3),
        MomentOfInertia(4),
        MomentOfInertia(0.1),
        MomentOfInertia(0.2),
        MomentOfInertia(0.3),
        Length(1),
    )
    var inertia = Matrix3()
    inertia.set(
        segment.xx.value,
        segment.xy.value,
        segment.xz.value,
        segment.xy.value,
        segment.yy.value,
        segment.yz.value,
        segment.xz.value,
        segment.yz.value,
        segment.zz.value,
    )
    # This proper rotation maps (x, y, z) to (z, x, y).
    var basis = Matrix3()
    basis.set(0, 0, 1, 1, 0, 0, 0, 1, 0)
    var inverse = basis
    inverse.transpose()
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(1)),
        segment.mass,
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.set_center_of_mass(basis.transform(segment.center))
    body.set_inertia(basis * inertia * inverse)
    body.angular_velocity = Vector3(1, 0, 0)
    var momentum = body.angular_momentum()
    assert_almost_equal(body.center_of_mass.x, 3, atol=1e-6)
    assert_almost_equal(body.center_of_mass.y, 1, atol=1e-6)
    assert_almost_equal(body.center_of_mass.z, 2, atol=1e-6)
    assert_almost_equal(momentum.x, 4, atol=1e-5)
    assert_almost_equal(momentum.y, 0.2, atol=1e-5)
    assert_almost_equal(momentum.z, 0.3, atol=1e-5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
