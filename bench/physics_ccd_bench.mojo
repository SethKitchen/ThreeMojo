# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fixed vehicle/sensor-scale workloads for the scoped sphere/mesh sweep.

These synthetic spheres are collision probes, not a validated vehicle model.
All rows use the same triangles, moving probes, rays and repeat counts.
"""

from extensions.physics.body import BodyId, DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import DISCRETE, SPHERE_MESH_CCD
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import assert_true, assert_equal
from std.time import perf_counter_ns
from units.si import Length, Mass, Duration


def _world(side: Int, probes: Int, continuous: Bool) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    if continuous:
        world.collision_detection = SPHERE_MESH_CCD
    var triangles = List[Triangle]()
    for y in range(side):
        for x in range(side):
            var a = Vector3(Float32(x * 4), Float32(y * 4), 0)
            var b = a + Vector3(4, 0, 0)
            var c = a + Vector3(4, 4, 0)
            var d = a + Vector3(0, 4, 0)
            triangles.append(Triangle(a, b, c))
            triangles.append(Triangle(a, c, d))
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(triangles^),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    for i in range(probes):
        var ball = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.1)),
            Mass(1),
            Vector3(Float32(2 + 6 * i), 2, 0.15),
            Quaternion.identity(),
        )
        ball.material = PhysicsMaterial(0, 0)
        _ = world.add_body(ball^)
    return world^


def _reset(mut world: PhysicsWorld):
    for i in range(1, len(world.bodies)):
        world.bodies[i].position.z = 0.15
        world.bodies[i].linear_velocity = Vector3(0, 0, -30)


def _run(name: String, side: Int, probes: Int, rays: Int) raises:
    for continuous in [False, True]:
        var world = _world(side, probes, continuous)
        _reset(world)
        world.step(Duration(0.01))
        var step_total = Float64(0)
        var ray_total = Float64(0)
        var maximum = Float64(0)
        var checksum = Float64(0)
        for _ in range(20):
            _reset(world)
            var start = perf_counter_ns()
            world.step(Duration(0.01))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            step_total += elapsed
            maximum = max(maximum, elapsed)
            if continuous:
                assert_equal(world.contact_count, probes)
                for i in range(1, len(world.bodies)):
                    assert_true(world.bodies[i].position.z >= 0.09999)
            else:
                assert_equal(world.contact_count, 0)
            start = perf_counter_ns()
            for ray in range(rays):
                var x = Float32((ray * 17) % (side * 4)) + 0.25
                var y = Float32((ray * 29) % (side * 4)) + 0.25
                var hit = world.raycast(
                    Vector3(x, y, 5), Vector3(0, 0, -1), Length(10), BodyId(-1)
                )
                assert_true(Bool(hit))
                checksum += Float64(hit.value().distance)
            ray_total += Float64(perf_counter_ns() - start) / 1000000
        print(
            name,
            ",",
            continuous,
            ",",
            2 * side * side,
            ",",
            probes,
            ",",
            rays,
            ",",
            step_total / 20,
            ",",
            maximum,
            ",",
            ray_total / 20,
            ",",
            checksum,
            sep="",
        )


def main() raises:
    print(
        "scene,ccd,triangles,spheres,rays,mean_step_ms,max_step_ms,mean_ray_batch_ms,checksum"
    )
    _run("vehicle-probe", 32, 1, 64)
    _run("separated-fleet", 64, 32, 256)
    _run("sensor-scale", 128, 16, 2048)
