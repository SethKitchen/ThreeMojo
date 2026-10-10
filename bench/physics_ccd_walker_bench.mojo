# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Walker capsules and spinning anisotropic spheres on a terrain mesh.

`physics_ccd_bench.mojo` times isotropic sphere probes and stays fixed.
This bench times the two later CCD contracts: rotation-locked capsules,
as character and walker bodies use, and spheres with an anisotropic
inertia tensor that spin into the ground with friction. The bodies are
collision probes, not validated walker or vehicle models.

Run it with `mojo run -I . bench/physics_ccd_walker_bench.mojo`.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import assert_true
from std.time import perf_counter_ns
from units.si import Length, Mass, Duration

comptime _RADIUS = Float32(0.3)
comptime _HALF = Float32(0.6)


def _ground(side: Int) -> List[Triangle]:
    # A gently rolling terrain, 4 m cells, z up.
    var triangles = List[Triangle]()
    for y in range(side):
        for x in range(side):
            var corners = List[Vector3]()
            for corner in [(0, 0), (1, 0), (1, 1), (0, 1)]:
                var cx = x + corner[0]
                var cy = y + corner[1]
                var z = Float32(((cx * 7 + cy * 13) % 5)) * 0.04
                corners.append(Vector3(Float32(cx * 4), Float32(cy * 4), z))
            triangles.append(Triangle(corners[0], corners[1], corners[2]))
            triangles.append(Triangle(corners[0], corners[2], corners[3]))
    return triangles^


def _tensor(xx: Float32, yy: Float32, zz: Float32) -> Matrix3:
    var tensor = Matrix3()
    tensor.elements[0] = xx
    tensor.elements[4] = yy
    tensor.elements[8] = zz
    return tensor


def _world(
    side: Int, bodies: Int, walkers: Bool, continuous: Bool
) raises -> PhysicsWorld:
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
    for i in range(bodies):
        var at = Vector3(
            Float32(2 + 6 * (i % 16)), Float32(2 + 6 * (i // 16)), 0
        )
        if walkers:
            var body = RigidBody(
                DYNAMIC,
                Shape.capsule(Length(_RADIUS), Length(_HALF)),
                Mass(70),
                at,
                Quaternion.identity(),
            )
            # Rotation-locked: every inverse inertia element is zero.
            body.set_inverse_inertia(_tensor(0, 0, 0))
            body.material = PhysicsMaterial(0.8, 0)
            _ = world.add_body(body^)
        else:
            var body = RigidBody(
                DYNAMIC,
                Shape.sphere(Length(0.1)),
                Mass(1),
                at,
                Quaternion.identity(),
            )
            body.set_inverse_inertia(_tensor(250, 500, 125))
            body.material = PhysicsMaterial(0.5, 0.2)
            _ = world.add_body(body^)
    return world^


def _reset(mut world: PhysicsWorld, walkers: Bool):
    # Each step starts just above the terrain, moving fast into it.
    var lift = _RADIUS + _HALF + 0.25 if walkers else Float32(0.35)
    for i in range(1, len(world.bodies)):
        world.bodies[i].position.z = lift
        world.bodies[i].linear_velocity = Vector3(1.5, -0.5, -30)
        if not walkers:
            world.bodies[i].angular_velocity = Vector3(3, 1, -2)


def _run(name: String, side: Int, bodies: Int, walkers: Bool) raises:
    for continuous in [False, True]:
        var world = _world(side, bodies, walkers, continuous)
        _reset(world, walkers)
        world.step(Duration(0.01))
        var total = Float64(0)
        var maximum = Float64(0)
        var lowest = Float32(1e9)
        for _ in range(20):
            _reset(world, walkers)
            var start = perf_counter_ns()
            world.step(Duration(0.01))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            total += elapsed
            maximum = max(maximum, elapsed)
            for i in range(1, len(world.bodies)):
                lowest = min(lowest, world.bodies[i].position.z)
        var floor = _RADIUS + _HALF if walkers else Float32(0.1)
        if continuous:
            # A body can slide on into a neighboring sloped cell.
            assert_true(world.contact_count >= bodies)
            # The terrain's lowest corner is at 0 m. No body sinks below it.
            assert_true(lowest >= floor - 0.0001)
        print(
            name,
            ",",
            continuous,
            ",",
            2 * side * side,
            ",",
            bodies,
            ",",
            total / 20,
            ",",
            maximum,
            ",",
            lowest,
            sep="",
        )


def main() raises:
    print("scene,ccd,triangles,bodies,mean_step_ms,max_step_ms,lowest_z_m")
    _run("walker", 32, 1, True)
    _run("walker-crowd", 64, 64, True)
    _run("spinning-probe", 32, 1, False)
    _run("spinning-fleet", 64, 64, False)
