# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Car-sized boxes that only translate, landing on a ground mesh.

CCD sweeps a box or hull that cannot turn exactly, by the separating-axis
test over time. This bench times that for one box and for 64 boxes, the
size of a car chassis, that land fast on a flat ground of 8,192 triangles
while they slide forward. The boxes are collision probes, not validated
vehicle models: a real chassis turns, and CCD refuses a turning box.

After every timed step, and outside the timing, a CCD row checks each box:
an event names its contact with the ground, and its lowest corner is not
below the ground by more than `_TOLERANCE`. Controls first show that the
check rejects a box sunk into the ground and a missing contact.

Run it with `mojo run -I . bench/physics_ccd_box_bench.mojo`.
"""

from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    STATIC,
    RigidBody,
    locked_inverse_inertia,
)
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.shape import PhysicsMaterial, Shape
from bench.contacts import bodies_missing_contact
from extensions.physics.world import CollisionEvent, PhysicsWorld
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from units.si import Duration, Length, Mass

# Half the size of a car's body, in meters: 2.25 long, 0.9 wide, 0.7 high.
comptime _HALF = Vector3(2.25, 0.9, 0.7)
comptime _TOLERANCE = Float64(0.001)


def _ground(side: Int) -> List[Triangle]:
    # A flat ground of 4 m cells, z up, with two triangles in each cell.
    var triangles = List[Triangle]()
    for y in range(side):
        for x in range(side):
            var a = Vector3(Float32(x * 4), Float32(y * 4), 0)
            var b = Vector3(Float32(x * 4 + 4), Float32(y * 4), 0)
            var c = Vector3(Float32(x * 4 + 4), Float32(y * 4 + 4), 0)
            var d = Vector3(Float32(x * 4), Float32(y * 4 + 4), 0)
            triangles.append(Triangle(a, b, c))
            triangles.append(Triangle(a, c, d))
    return triangles^


def _lowest(body: RigidBody) -> Float64:
    # The lowest corner of an axis-aligned box that cannot turn.
    return Float64(body.position.z) - Float64(_HALF.z)


def _box(at: Vector3) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(_HALF.x), Length(_HALF.y), Length(_HALF.z)),
        Mass(1500),
        at,
        Quaternion.identity(),
    )
    # A box that cannot turn: every inverse inertia element is zero.
    body.set_inverse_inertia(locked_inverse_inertia())
    body.material = PhysicsMaterial(0.8, 0.1)
    return body^


def _controls() raises:
    # A box with its lowest corner 5 cm under the ground is rejected.
    var sunk = _box(Vector3(10, 10, 0.65))
    assert_true(_lowest(sunk) < -_TOLERANCE)
    var resting = _box(Vector3(10, 10, 0.7005))
    assert_true(_lowest(resting) > -_TOLERANCE)
    # Repeated events for one box cannot stand in for another.
    var events = List[CollisionEvent]()
    for _ in range(3):
        events.append(CollisionEvent(BodyId(1), BodyId(0), Vector3(0, 0, 1)))
    assert_equal(bodies_missing_contact(events, 2), 1)


def _world(side: Int, boxes: Int, continuous: Bool) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, -9.81)
    if continuous:
        world.collision_detection = SPHERE_MESH_CCD
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(_ground(side)),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    for i in range(boxes):
        _ = world.add_body(
            _box(
                Vector3(
                    Float32(4 + 8 * (i % 16)), Float32(4 + 8 * (i // 16)), 1
                )
            )
        )
    return world^


def _reset(mut world: PhysicsWorld):
    # Each step starts every box 0.1 m above the ground, falling at 30 m/s
    # and sliding forward at 15 m/s.
    for i in range(1, len(world.bodies)):
        world.bodies[i].position.z = _HALF.z + 0.1
        world.bodies[i].linear_velocity = Vector3(15, 0, -30)


def _run(name: String, side: Int, boxes: Int) raises:
    for continuous in [False, True]:
        var world = _world(side, boxes, continuous)
        _reset(world)
        world.step(Duration(0.01))
        var total = Float64(0)
        var maximum = Float64(0)
        var least = Float64(1e9)
        for _ in range(20):
            _reset(world)
            var start = perf_counter_ns()
            world.step(Duration(0.01))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            total += elapsed
            maximum = max(maximum, elapsed)
            # Validation runs after the timed step.
            for i in range(1, len(world.bodies)):
                least = min(least, _lowest(world.bodies[i]))
            if continuous:
                assert_equal(bodies_missing_contact(world.events, boxes), 0)
        if continuous:
            assert_true(least > -_TOLERANCE, String(least))
        print(
            name,
            ",",
            continuous,
            ",",
            2 * side * side,
            ",",
            boxes,
            ",",
            total / 20,
            ",",
            maximum,
            ",",
            least,
            sep="",
        )


def main() raises:
    _controls()
    print("scene,ccd,triangles,boxes,mean_step_ms,max_step_ms,least_gap_m")
    _run("box", 32, 1)
    _run("box-fleet", 64, 64)
