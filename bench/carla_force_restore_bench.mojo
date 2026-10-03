# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare all-body and dynamic-only tick force snapshots on Linux.

Arguments: bodies, dynamic percent, substeps, ticks, strategy, optional hook.
Strategies: all (production), indexed (packed dynamic records), branch
(all snapshots, conditional restoration). Warm-up and setup are not timed.
Use navigation_allocations.c for a separate allocation run; do not compare
hook-instrumented time with native time. Linux clock() uses 1,000,000 ticks/s.
"""

from extensions.carla.physics.body import DYNAMIC, KINEMATIC, STATIC, RigidBody
from extensions.carla.physics.simulation import CarlaPhysics
from extensions.carla.physics.world import CollisionEvent
from extensions.carla.physics.shape import Shape
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.ffi import OwnedDLHandle, external_call
from std.sys import argv
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from units.si import Duration, Length, Mass, SECOND


@fieldwise_init
struct _SavedForce(ImplicitlyCopyable):
    var body: Int
    var force: Vector3
    var torque: Vector3


def _candidate_tick[
    branch: Bool
](mut sim: CarlaPhysics, dt: Duration, substeps: Int) raises:
    if substeps < 1:
        raise Error("A tick needs at least one substep")
    if not (dt.value > 0):
        raise Error("A tick must be more than zero")
    var h = Duration(dt.value / Float32(substeps), SECOND)
    sim.events = List[CollisionEvent]()
    var saved = List[_SavedForce]()
    var forces = List[Vector3]()
    var torques = List[Vector3]()
    for i in range(len(sim.world.bodies)):
        ref body = sim.world.bodies[i]
        comptime if branch:
            forces.append(body.force)
            torques.append(body.torque)
        else:
            if body.kind() == DYNAMIC:
                saved.append(_SavedForce(i, body.force, body.torque))
    for _ in range(substeps):
        comptime if branch:
            for i in range(len(forces)):
                if sim.world.bodies[i].kind() == DYNAMIC:
                    sim.world.bodies[i].force = forces[i]
                    sim.world.bodies[i].torque = torques[i]
        else:
            for entry in saved:
                sim.world.bodies[entry.body].force = entry.force
                sim.world.bodies[entry.body].torque = entry.torque
        for i in range(len(sim.vehicles)):
            sim.vehicles[i].update(sim.world, h)
        for i in range(len(sim.walkers)):
            sim.walkers[i].update(sim.world, h)
        sim.world.step(h)
        sim.events.extend(sim.world.events.copy())


def _world(count: Int, percent: Int) raises -> CarlaPhysics:
    var sim = CarlaPhysics()
    sim.world.gravity = Vector3(0, 0, 0)
    for i in range(count):
        # Interleave dynamic and static bodies; spatially separate all shapes.
        var dynamic = (i * 37) % 100 < percent
        var body = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(1)),
            Mass(2),
            Vector3(Float32(i) * 4, 0, 0),
            Quaternion.identity(),
        )
        body.set_kind(DYNAMIC if dynamic else STATIC)
        _ = sim.add_body(body^)
    return sim^


def _forces(mut sim: CarlaPhysics):
    for i in range(len(sim.world.bodies)):
        sim.world.bodies[i].force = Vector3(0, 2, 0)
        sim.world.bodies[i].torque = Vector3(0, 0, 0.8)


def _tick[
    indexed: Bool, branch: Bool
](mut sim: CarlaPhysics, substeps: Int) raises:
    comptime if indexed or branch:
        _candidate_tick[branch](sim, Duration(0.01, SECOND), substeps)
    else:
        sim.tick(Duration(0.01, SECOND), substeps)


def _batch[
    indexed: Bool, branch: Bool
](mut sim: CarlaPhysics, substeps: Int, ticks: Int) raises:
    for _ in range(ticks):
        _forces(sim)
        _tick[indexed, branch](sim, substeps)


def _run[
    indexed: Bool, branch: Bool
](count: Int, percent: Int, substeps: Int, ticks: Int, hook: String) raises:
    var sim = _world(count, percent)
    _batch[indexed, branch](sim, substeps, 3)
    var start = perf_counter_ns()
    var cpu_start = external_call["clock", Int]()
    _batch[indexed, branch](sim, substeps, ticks)
    var cpu_ticks = external_call["clock", Int]() - cpu_start
    var ns = perf_counter_ns() - start
    var peak = UInt64(0)
    var total = UInt64(0)
    var calls = UInt64(0)
    if hook:
        var library = OwnedDLHandle(hook)
        assert_equal(
            library.call["navigation_allocations_selftest", UInt64](), 1
        )
        _ = library.call["navigation_allocations_begin", UInt64]()
        _batch[indexed, branch](sim, substeps, 1)
        peak = library.call["navigation_allocations_end", UInt64]()
        total = library.call["navigation_allocations_total", UInt64]()
        calls = library.call["navigation_allocations_calls", UInt64]()
        assert_equal(
            library.call["navigation_allocations_overflow", UInt64](), 0
        )
    var checksum = Float64(0)
    for body in sim.world.bodies:
        assert_true(body.force == Vector3(0, 0, 0))
        assert_true(body.torque == Vector3(0, 0, 0))
        checksum += Float64(body.linear_velocity.y + body.angular_velocity.z)
    print(
        "wall_ns",
        ns,
        "cpu_ns",
        cpu_ticks * 1000,
        "peak_bytes",
        peak,
        "total_bytes",
        total,
        "allocations",
        calls,
        "checksum",
        checksum,
    )


def _verify_candidates[branch: Bool]() raises:
    for substeps in [1, 5, 10]:
        for percent in [0, 10, 100]:
            var original = _world(20, percent)
            var candidate = _world(20, percent)
            for tick in range(4):
                for i in range(20):
                    # Ghosts remain dynamic force consumers. Body modes can
                    # change between ticks, without a retained index cache.
                    original.world.bodies[i].collides = i % 3 != 0
                    candidate.world.bodies[i].collides = i % 3 != 0
                    if tick == 1:
                        var kind = DYNAMIC if i % 2 == 0 else KINEMATIC
                        original.world.bodies[i].set_kind(kind)
                        candidate.world.bodies[i].set_kind(kind)
                    elif tick == 3:
                        original.world.bodies[i].set_kind(DYNAMIC)
                        candidate.world.bodies[i].set_kind(DYNAMIC)
                if tick % 2 == 0:
                    _forces(original)
                    _forces(candidate)
                original.tick(Duration(0.01, SECOND), substeps)
                _candidate_tick[branch](
                    candidate, Duration(0.01, SECOND), substeps
                )
                assert_equal(
                    original.world.contact_count, candidate.world.contact_count
                )
                assert_equal(len(original.events), len(candidate.events))
                for i in range(20):
                    ref a = original.world.bodies[i]
                    ref b = candidate.world.bodies[i]
                    assert_true(a.position == b.position)
                    assert_true(a.linear_velocity == b.linear_velocity)
                    assert_true(a.angular_velocity == b.angular_velocity)
                    assert_true(a.force == b.force)
                    assert_true(a.torque == b.torque)
                    assert_equal(a.rotation.x, b.rotation.x)
                    assert_equal(a.rotation.y, b.rotation.y)
                    assert_equal(a.rotation.z, b.rotation.z)
                    assert_equal(a.rotation.w, b.rotation.w)


def main() raises:
    _verify_candidates[False]()
    _verify_candidates[True]()
    var args = argv()
    if len(args) != 6 and len(args) != 7:
        raise Error(
            "Pass bodies, dynamic percent, substeps, ticks, strategy, optional"
            " hook"
        )
    var count = Int(args[1])
    var percent = Int(args[2])
    var substeps = Int(args[3])
    var ticks = Int(args[4])
    assert_true(count > 0 and percent >= 0 and percent <= 100)
    assert_true(substeps > 0 and ticks > 0)
    var hook = String(args[6]) if len(args) == 7 else String("")
    if args[5] == "all":
        _run[False, False](count, percent, substeps, ticks, hook)
    elif args[5] == "indexed":
        _run[True, False](count, percent, substeps, ticks, hook)
    elif args[5] == "branch":
        _run[False, True](count, percent, substeps, ticks, hook)
    else:
        raise Error("Strategy must be all, indexed, or branch")
