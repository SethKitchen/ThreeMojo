# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Interacting moving spheres under CCD: pairs, chains and struck stacks.

`physics_ccd_walker_bench.mojo` times bodies that never meet. This bench
times groups of spheres that hit each other within one step, as CCD now
sweeps them together. The bodies are collision probes, not validated
vehicle, walker or granular models. CCD still refuses boxes and convex
hulls, so a vehicle chassis is not measured.

After every timed step, and outside the timing, the bench checks each
group with code that shares nothing with the solver: no two spheres
overlap by more than `_TOLERANCE`, no sphere is under the floor by more
than `_TOLERANCE`, linear momentum along the motion is kept where no
floor acts, and kinetic energy does not rise. Controls first show that
the checks reject an overlap, a sphere in the floor and an energy gain.

It also times a step that exhausts the impact limit and rolls back, and
reports the rollback storage that a step keeps.

Run it with `mojo run -I . bench/physics_ccd_pairs_bench.mojo`.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import DISCRETE, SPHERE_MESH_CCD
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import CollisionEvent, PhysicsWorld, _StepState
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import sqrt
from std.sys import size_of
from std.testing import assert_true
from std.time import perf_counter_ns
from units.si import Length, Mass, Duration

comptime _RADIUS = Float32(0.1)
# This bench's numerical allowance for Float32 positions near 100 m.
comptime _TOLERANCE = Float64(0.001)
comptime _STEP = Float32(0.01)
comptime _GROUPS = 64


def _floor() raises -> RigidBody:
    # Two large triangles at z = 0, z up.
    var a = Vector3(-10, -10, 0)
    var b = Vector3(110, -10, 0)
    var c = Vector3(110, 110, 0)
    var d = Vector3(-10, 110, 0)
    return RigidBody(
        STATIC,
        Shape.mesh([Triangle(a, b, c), Triangle(a, c, d)]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _sphere(at: Vector3, mass: Float32, bounce: Float32) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(_RADIUS)),
        Mass(mass),
        at,
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0.3, bounce)
    return body^


def _members(scene: String) -> Int:
    if scene == "chains":
        return 4
    return 2


def _bounce(scene: String) -> Float32:
    # Pairs rebound partly, chains pass the energy along, stacks settle.
    if scene == "pairs":
        return 0.5
    if scene == "chains":
        return 1
    return 0


def _world(scene: String, continuous: Bool) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    if continuous:
        world.collision_detection = SPHERE_MESH_CCD
    _ = world.add_body(_floor())
    for g in range(_GROUPS):
        var x = Float32(6 * (g % 8))
        var y = Float32(6 * (g // 8))
        for k in range(_members(scene)):
            var at = Vector3(x + Float32(k) * 0.3, y, 0.3)
            if scene == "stacks":
                at = Vector3(x, y, 0.1 + Float32(k) * 0.4)
            _ = world.add_body(
                _sphere(
                    at,
                    1 + Float32(k % 2),
                    _bounce(scene),
                )
            )
    return world^


def _reset(mut world: PhysicsWorld, scene: String):
    # Each step starts the groups where `_world` put them.
    for g in range(_GROUPS):
        var x = Float32(6 * (g % 8))
        var y = Float32(6 * (g // 8))
        for k in range(_members(scene)):
            var i = 1 + g * _members(scene) + k
            ref body = world.bodies[i]
            body.angular_velocity = Vector3(0, 0, 0)
            if scene == "stacks":
                # B rests on the floor; A falls onto it.
                body.position = Vector3(x, y, 0.1 + Float32(k) * 0.4)
                body.linear_velocity = Vector3(
                    0, 0, Float32(-30) if k == 1 else Float32(0)
                )
            else:
                body.position = Vector3(x + Float32(k) * 0.3, y, 0.3)
                var speed = Float32(0)
                if k == 0:
                    speed = 30
                elif scene == "pairs":
                    speed = -30
                body.linear_velocity = Vector3(speed, 0.5, 0)


def _energy(world: PhysicsWorld, first: Int, count: Int) -> Float64:
    var total = Float64(0)
    for i in range(first, first + count):
        ref body = world.bodies[i]
        var v = body.linear_velocity
        total += Float64(v.dot(v)) / Float64(body.inverse_mass())
        var w = body.angular_velocity
        # A solid sphere: I = 2/5 m r^2.
        total += (
            0.4
            * Float64(_RADIUS * _RADIUS)
            * Float64(w.dot(w))
            / Float64(body.inverse_mass())
        )
    return total


def _momentum_x(world: PhysicsWorld, first: Int, count: Int) -> Float64:
    var total = Float64(0)
    for i in range(first, first + count):
        ref body = world.bodies[i]
        total += Float64(body.linear_velocity.x) / Float64(body.inverse_mass())
    return total


def _overlap(world: PhysicsWorld, first: Int, count: Int) -> Float64:
    """Return the deepest overlap in a group: between two members, or of a
    member with the floor, in meters. Zero or less means none."""
    var deepest = Float64(-1e9)
    for i in range(first, first + count):
        var p = world.bodies[i].position
        deepest = max(deepest, Float64(_RADIUS) - Float64(p.z))
        for j in range(i + 1, first + count):
            var q = world.bodies[j].position
            var dx = Float64(p.x) - Float64(q.x)
            var dy = Float64(p.y) - Float64(q.y)
            var dz = Float64(p.z) - Float64(q.z)
            deepest = max(
                deepest,
                2 * Float64(_RADIUS) - sqrt(dx * dx + dy * dy + dz * dz),
            )
    return deepest


def _crossed(
    world: PhysicsWorld, first: Int, count: Int, scene: String
) -> Bool:
    """Return whether two neighbors in a group passed through each other:
    their order along the motion turned round."""
    for i in range(first, first + count - 1):
        var p = world.bodies[i].position
        var q = world.bodies[i + 1].position
        if scene == "stacks":
            if p.z > q.z:
                return True
        elif p.x > q.x:
            return True
    return False


def _controls() raises:
    var world = _world("pairs", True)
    _reset(world, "pairs")
    # Two members on top of each other overlap; one in the floor too.
    world.bodies[2].position = world.bodies[1].position + Vector3(0.1, 0, 0)
    assert_true(_overlap(world, 1, 2) > _TOLERANCE)
    _reset(world, "pairs")
    world.bodies[1].position.z = 0.05
    assert_true(_overlap(world, 1, 2) > _TOLERANCE)
    _reset(world, "pairs")
    assert_true(_overlap(world, 1, 2) <= 0)
    assert_true(not _crossed(world, 1, 2, "pairs"))
    world.bodies[1].position.x += 1
    assert_true(_crossed(world, 1, 2, "pairs"))
    _reset(world, "pairs")
    # A faster member is an energy gain.
    var before = _energy(world, 1, 2)
    world.bodies[1].linear_velocity.x = 31
    assert_true(_energy(world, 1, 2) > before)


def _run(scene: String) raises:
    var members = _members(scene)
    for continuous in [False, True]:
        var world = _world(scene, continuous)
        _reset(world, scene)
        world.step(Duration(_STEP))
        var total = Float64(0)
        var maximum = Float64(0)
        var deepest = Float64(-1e9)
        var impacts = 0
        var crossed = 0
        for _ in range(20):
            _reset(world, scene)
            var energy = List[Float64]()
            var momentum = List[Float64]()
            for g in range(_GROUPS):
                energy.append(_energy(world, 1 + g * members, members))
                momentum.append(_momentum_x(world, 1 + g * members, members))
            var start = perf_counter_ns()
            world.step(Duration(_STEP))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            total += elapsed
            maximum = max(maximum, elapsed)
            impacts += len(world.events) // 2
            # Validation runs after the timed step.
            for g in range(_GROUPS):
                var first = 1 + g * members
                deepest = max(deepest, _overlap(world, first, members))
                if _crossed(world, first, members, scene):
                    crossed += 1
                if continuous:
                    assert_true(
                        _energy(world, first, members)
                        <= energy[g] * 1.000001 + 1e-9
                    )
                    if scene != "stacks":
                        assert_true(
                            abs(
                                _momentum_x(world, first, members) - momentum[g]
                            )
                            <= 1e-4 * (1 + abs(momentum[g]))
                        )
        if continuous:
            assert_true(deepest <= _TOLERANCE, String(deepest))
            assert_true(crossed == 0, String(crossed))
        print(
            scene,
            ",",
            continuous,
            ",",
            _GROUPS * members,
            ",",
            total / 20,
            ",",
            maximum,
            ",",
            Float64(impacts) / 20,
            ",",
            deepest,
            ",",
            Float64(crossed) / 20,
            sep="",
        )


def _rollback() raises:
    # One impact a body cannot finish a struck stack: the step rolls back.
    var world = _world("stacks", True)
    world.ccd_max_impacts = 1
    var total = Float64(0)
    for _ in range(20):
        _reset(world, "stacks")
        var start = perf_counter_ns()
        try:
            world.step(Duration(_STEP))
        except:
            pass
        total += Float64(perf_counter_ns() - start) / 1000000
        # The rolled-back state is the reset state.
        assert_true(world.bodies[2].linear_velocity.z == -30)
        assert_true(world.bodies[1].position.z == Float32(0.1))
    var bodies = len(world.bodies)
    print(
        "rollback-stacks,True,",
        bodies - 1,
        ",",
        total / 20,
        ",bytes_per_body=",
        size_of[_StepState](),
        ",state_bytes=",
        bodies * size_of[_StepState](),
        sep="",
    )


def main() raises:
    _controls()
    print(
        "scene,ccd,spheres,mean_step_ms,max_step_ms,impacts_per_step,deepest_m,crossed_groups_per_step"
    )
    _run("pairs")
    _run("chains")
    _run("stacks")
    _rollback()
