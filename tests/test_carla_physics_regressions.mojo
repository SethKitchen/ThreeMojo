# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regression checks for static primitive contacts and tick-level forces."""

from extensions.carla.physics.body import DYNAMIC, KINEMATIC, STATIC, RigidBody
from extensions.carla.physics.shape import Shape
from extensions.carla.physics.simulation import CarlaPhysics
from extensions.carla.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Duration, KILOGRAM, Length, METER, Mass, SECOND


def test_static_primitives_stop_a_dynamic_sphere() raises:
    var shapes = List[Shape]()
    shapes.append(Shape.box(Length(1), Length(1), Length(1)))
    shapes.append(Shape.sphere(Length(1)))
    shapes.append(Shape.capsule(Length(1), Length(0.5)))
    shapes.append(
        Shape.convex(
            [
                Vector3(-1, -1, -1),
                Vector3(1, -1, -1),
                Vector3(1, 1, -1),
                Vector3(-1, 1, -1),
                Vector3(-1, -1, 1),
                Vector3(1, -1, 1),
                Vector3(1, 1, 1),
                Vector3(-1, 1, 1),
            ]
        )
    )
    for shape in shapes:
        var world = PhysicsWorld()
        world.gravity = Vector3(0, 0, 0)
        _ = world.add_body(
            RigidBody(
                STATIC,
                shape.copy(),
                Mass(0),
                Vector3(0, 0, 0),
                Quaternion.identity(),
            )
        )
        var ball = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.5)),
            Mass(1),
            Vector3(-2, 0, 0),
            Quaternion.identity(),
        )
        ball.linear_velocity = Vector3(1, 0, 0)
        var id = world.add_body(ball^)
        var contacts = 0
        for _ in range(300):
            world.step(Duration(0.01, SECOND))
            contacts += world.contact_count
        assert_true(contacts > 0)
        assert_almost_equal(world.bodies[id.value].position.x, -1.5, atol=0.006)
        assert_almost_equal(
            world.bodies[id.value].linear_velocity.x, 0, atol=1e-5
        )


def test_dynamic_box_and_capsule_meet_static_round_shapes() raises:
    for use_box in [True, False]:
        var world = PhysicsWorld()
        world.gravity = Vector3(0, 0, 0)
        var moving = Shape.capsule(Length(0.5), Length(0.5))
        var fixed = Shape.sphere(Length(1))
        if use_box:
            moving = Shape.box(Length(0.5), Length(0.5), Length(0.5))
            fixed = Shape.capsule(Length(1), Length(0.5))
        var body = RigidBody(
            DYNAMIC,
            moving^,
            Mass(1),
            Vector3(-2, 0, 0),
            Quaternion.identity(),
        )
        body.linear_velocity = Vector3(1, 0, 0)
        var id = world.add_body(body^)
        # Insert the static after the dynamic to exercise reversed pair order.
        _ = world.add_body(
            RigidBody(
                STATIC,
                fixed^,
                Mass(0),
                Vector3(0, 0, 0),
                Quaternion.identity(),
            )
        )
        var contacts = 0
        for _ in range(300):
            world.step(Duration(0.01, SECOND))
            contacts += world.contact_count
        assert_true(contacts > 0)
        assert_almost_equal(world.bodies[id.value].position.x, -1.5, atol=0.006)
        assert_almost_equal(
            world.bodies[id.value].linear_velocity.x, 0, atol=1e-5
        )


def test_external_force_and_torque_span_the_tick() raises:
    for substeps in [1, 5, 10]:
        var sim = CarlaPhysics()
        sim.world.gravity = Vector3(0, 0, 0)
        var id = sim.add_body(
            RigidBody(
                DYNAMIC,
                Shape.sphere(Length(1, METER)),
                Mass(2, KILOGRAM),
                Vector3(0, 0, 0),
                Quaternion.identity(),
            )
        )
        sim.world.bodies[id.value].add_force(
            Vector3(20, 0, 0), Vector3(0, 0, 0)
        )
        sim.world.bodies[id.value].torque = Vector3(0, 0, 8)
        sim.tick(Duration(0.05, SECOND), substeps)
        # F t / m = 0.5; T t / I = 0.5 with I = 2/5 m r^2 = 0.8.
        assert_almost_equal(sim.velocity(id).x, 0.5, atol=1e-6)
        assert_almost_equal(sim.angular_velocity(id).z, 0.5, atol=1e-6)
        # The next tick receives no force or torque from the prior tick.
        sim.tick(Duration(0.05, SECOND), substeps)
        assert_almost_equal(sim.velocity(id).x, 0.5, atol=1e-6)
        assert_almost_equal(sim.angular_velocity(id).z, 0.5, atol=1e-6)


def test_empty_simulation_ticks_without_bodies_or_events() raises:
    var sim = CarlaPhysics()
    for substeps in [1, 4]:
        sim.tick(Duration(0.05, SECOND), substeps)
        assert_equal(len(sim.world.bodies), 0)
        assert_equal(len(sim.events), 0)
        assert_equal(sim.world.contact_count, 0)


def test_tick_force_consumption_across_body_kinds_and_ghosts() raises:
    for substeps in [1, 5, 10]:
        for kind in [STATIC, KINEMATIC, DYNAMIC]:
            for ghost in [False, True]:
                var sim = CarlaPhysics()
                sim.world.gravity = Vector3(0, 0, 0)
                var body = RigidBody(
                    DYNAMIC,
                    Shape.sphere(Length(1)),
                    Mass(2),
                    Vector3(0, 0, 0),
                    Quaternion.identity(),
                )
                body.set_kind(kind)
                body.collides = not ghost
                body.force = Vector3(20, 0, 0)
                body.torque = Vector3(0, 0, 8)
                _ = sim.add_body(body^)
                sim.tick(Duration(0.05, SECOND), substeps)
                var expected = Float32(0.5) if kind == DYNAMIC else Float32(0)
                assert_almost_equal(
                    sim.world.bodies[0].linear_velocity.x, expected, atol=1e-6
                )
                assert_almost_equal(
                    sim.world.bodies[0].angular_velocity.z, expected, atol=1e-6
                )
                assert_true(sim.world.bodies[0].force == Vector3(0, 0, 0))
                assert_true(sim.world.bodies[0].torque == Vector3(0, 0, 0))
                # A later dynamic mode must not revive consumed forces.
                sim.world.bodies[0].set_kind(DYNAMIC)
                sim.tick(Duration(0.05, SECOND), substeps)
                assert_almost_equal(
                    sim.world.bodies[0].linear_velocity.x, expected, atol=1e-6
                )
                assert_almost_equal(
                    sim.world.bodies[0].angular_velocity.z, expected, atol=1e-6
                )
                # Mode changes before a tick retain that tick's pending input.
                sim.world.bodies[0].set_kind(STATIC)
                sim.world.bodies[0].force = Vector3(20, 0, 0)
                sim.world.bodies[0].torque = Vector3(0, 0, 8)
                sim.world.bodies[0].set_kind(KINEMATIC)
                sim.world.bodies[0].set_kind(DYNAMIC)
                sim.tick(Duration(0.05, SECOND), substeps)
                assert_almost_equal(
                    sim.world.bodies[0].linear_velocity.x,
                    0.5,
                    atol=1e-6,
                )
                assert_almost_equal(
                    sim.world.bodies[0].angular_velocity.z,
                    0.5,
                    atol=1e-6,
                )
                assert_true(sim.world.bodies[0].force == Vector3(0, 0, 0))
                assert_true(sim.world.bodies[0].torque == Vector3(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
