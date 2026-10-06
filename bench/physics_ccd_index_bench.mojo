# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare the CCD index with the retained brute-force CCD oracle.

Build and run from the repository root, with the pinned Mojo 1.1.0 toolchain:
    mojo build -I . bench/physics_ccd_index_bench.mojo -o /tmp/ccd-index-bench
    /tmp/ccd-index-bench > /tmp/ccd-index-native.csv
    cc -shared -fPIC -O2 bench/navigation_allocations.c -o /tmp/navalloc.so
    LD_PRELOAD=/tmp/navalloc.so /tmp/ccd-index-bench /tmp/navalloc.so \
        > /tmp/ccd-index-allocations.csv

Run native timings without the allocation hook. Hooked timings are diagnostic.
The reused meter checks the preload hook's selftest and overflow flag. Bytes
are Mojo runtime requested bytes, not allocator overhead or process RSS. Peak
bytes include only allocations requested after that phase begins; they exclude
all live allocations from earlier phases. An
unhooked row has zero allocation counters; these zeros mean not measured.
Retained bytes are node-capacity payload only: capacity times the native node
size. They exclude the
world's preexisting triangle snapshot, octree, and temporary build storage.

The three fixed scenes import their construction and reset without changes.
Each path has one cold warmup step and exactly 20 measured complete steps and
ray batches. Warm timed step and ray order alternate by repetition parity;
the cold pair remains brute-first. Both paths use SPHERE_MESH_CCD. Every pair
must have identical
body state, contacts, events, and ray checksums. The final ray checksum remains
6400, 25600, and 204800 for the three fixed scenes, respectively.

Diagnostic phases use separate worlds. They are independent probes, not an
additive decomposition: validation and separation also occur inside a step;
positions includes separation, query, response, and ordering. The sphere-only
probe calls the production query/exact-solve/response path. The order-only
probe replays the exact stable insertion sort on those equal-time impacts. A
separately labeled synthetic ordering probe reverses distinct times on the
same number of records, prepared outside its timer. A full state
restore outside each measured probe prevents earlier probes from stopping the
sphere or changing the next input. The restore-copy replay allocates copies
of saved event/order lists; production rollback instead moves its backups.
The failed-step timing includes error-string identification and the assertion
that exhaustion occurred. Full restored-state checks are outside its timer.
Warm mean summaries use the maximum peak
bytes and the mean requested bytes and calls. Amortized rows are estimates:
(cold warmup + (lifetime - 1) * measured warm mean) / lifetime. They are not
extra measured steps. The worst-initial-overlap scene uses 2048 grid faces
and one long diagonal sweep; its first index query must return all 2048.
The rollback scene uses two bounce faces and 62 distant padding faces.
The measured cold sample includes both index and octree
construction. No speedup or break-even result is assumed in this source.
"""

from bench.physics_ccd_bench import _world, _reset
from bench.physics_static_bench import _Meter
from extensions.physics.body import BodyId, DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.ccd_index import _CCDIndex, _CCDNode
from extensions.physics.shape import Shape, PhysicsMaterial, _wide
from extensions.physics.world import (
    CollisionEvent,
    PhysicsWorld,
    _CCDImpact,
    _StepState,
)
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.sys import argv, size_of
from std.testing import assert_equal, assert_true
from units.si import Duration, Length, Mass


@fieldwise_init
struct _Saved(Copyable, Movable):
    var bodies: List[_StepState]
    var events: List[CollisionEvent]
    var order: List[Int]
    var contacts: Int
    var dirty: Bool


def _save(world: PhysicsWorld) -> _Saved:
    var states = List[_StepState]()
    for body in world.bodies:
        states.append(
            _StepState(
                body.position,
                body.rotation,
                body.linear_velocity,
                body.angular_velocity,
                body.force,
                body.torque,
                body.push_velocity,
                body.push_angular,
            )
        )
    return _Saved(
        states^,
        world.events.copy(),
        world._order.copy(),
        world.contact_count,
        world._dirty,
    )


def _restore(mut world: PhysicsWorld, saved: _Saved):
    # Deliberately keep the already-built static caches. These probes do not
    # change geometry. Restore all state that step's transaction protects.
    for i in range(len(saved.bodies)):
        world.bodies[i].position = saved.bodies[i].position
        world.bodies[i].rotation = saved.bodies[i].rotation
        world.bodies[i].linear_velocity = saved.bodies[i].velocity
        world.bodies[i].angular_velocity = saved.bodies[i].angular
        world.bodies[i].force = saved.bodies[i].force
        world.bodies[i].torque = saved.bodies[i].torque
        world.bodies[i].push_velocity = saved.bodies[i].push
        world.bodies[i].push_angular = saved.bodies[i].push_angular
    world.events = saved.events.copy()
    world._order = saved.order.copy()
    world.contact_count = saved.contacts
    world._dirty = saved.dirty


def _assert_saved(world: PhysicsWorld, saved: _Saved) raises:
    assert_equal(len(world.bodies), len(saved.bodies))
    for i in range(len(saved.bodies)):
        assert_true(world.bodies[i].position == saved.bodies[i].position)
        assert_true(world.bodies[i].rotation == saved.bodies[i].rotation)
        assert_true(world.bodies[i].linear_velocity == saved.bodies[i].velocity)
        assert_true(world.bodies[i].angular_velocity == saved.bodies[i].angular)
        assert_true(world.bodies[i].force == saved.bodies[i].force)
        assert_true(world.bodies[i].torque == saved.bodies[i].torque)
        assert_true(world.bodies[i].push_velocity == saved.bodies[i].push)
        assert_true(
            world.bodies[i].push_angular == saved.bodies[i].push_angular
        )
    assert_equal(world.contact_count, saved.contacts)
    assert_equal(world._order, saved.order)
    assert_equal(world._dirty, saved.dirty)
    assert_equal(len(world.events), len(saved.events))
    for i in range(len(saved.events)):
        assert_equal(world.events[i].body, saved.events[i].body)
        assert_equal(world.events[i].other, saved.events[i].other)
        assert_true(
            world.events[i].normal_impulse == saved.events[i].normal_impulse
        )


def _retained(world: PhysicsWorld) -> Int:
    return world._ccd_index.nodes.capacity() * size_of[_CCDNode]()


def _report(
    name: String,
    world: PhysicsWorld,
    spheres: Int,
    rays: Int,
    phase: String,
    repetition: Int,
    measured: Tuple[Int, UInt64, UInt64, UInt64],
    checksum: Float64 = 0,
):
    print(
        name,
        "brute" if world._ccd_brute_force else "indexed",
        phase,
        len(world._triangles),
        spheres,
        rays,
        repetition,
        measured[0],
        measured[1],
        measured[2],
        measured[3],
        _retained(world),
        checksum,
        sep=",",
    )


def _make(
    side: Int, probes: Int, distribution: Int, brute: Bool
) raises -> PhysicsWorld:
    if distribution != 1:
        var fixed = _world(side, probes, True)
        fixed._ccd_brute_force = brute
        return fixed^
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    var triangles = List[Triangle]()
    # Sixteen dense 8-by-8 patches, with 56-meter gaps between patches.
    # Each patch has one probe, so reachable moving balls are disjoint.
    for patch in range(16):
        for y in range(8):
            for x in range(8):
                var a = Vector3(
                    Float32((patch % 4) * 64 + x),
                    Float32((patch // 4) * 64 + y),
                    0,
                )
                var b = a + Vector3(1, 0, 0)
                var c = a + Vector3(1, 1, 0)
                var d = a + Vector3(0, 1, 0)
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
        var at = Vector3(
            Float32((i % 4) * 64) + 3.5,
            Float32((i // 4) * 64) + 3.5,
            0.15,
        )
        var ball = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.1)),
            Mass(1),
            at,
            Quaternion.identity(),
        )
        ball.material = PhysicsMaterial(0, 0)
        _ = world.add_body(ball^)
    return world^


def _reset_scene(mut world: PhysicsWorld, distribution: Int):
    _reset(world)
    if distribution == 2:
        # The diagonal sweep's AABB includes every grid triangle. Unlike
        # duplicate giant faces, this does not explode the contact octree.
        world.bodies[1].position = Vector3(-1, -1, 0.15)
        world.bodies[1].linear_velocity = Vector3(13000, 13000, -30)


def _ray_batch(
    world: PhysicsWorld, side: Int, rays: Int, distribution: Int
) raises -> Float64:
    var checksum = Float64(0)
    for ray in range(rays):
        # These are exactly the fixed benchmark ray coordinates for its rows.
        var x = Float32((ray * 17) % (side * 4)) + 0.25
        var y = Float32((ray * 29) % (side * 4)) + 0.25
        if distribution == 1:
            var patch = ray % 16
            x = Float32((patch % 4) * 64 + (ray * 17) % 8) + 0.25
            y = Float32((patch // 4) * 64 + (ray * 29) % 8) + 0.25
        var hit = world.raycast(
            Vector3(x, y, 5), Vector3(0, 0, -1), Length(10), BodyId(-1)
        )
        assert_true(Bool(hit))
        checksum += Float64(hit.value().distance)
    return checksum


def _assert_stopped(world: PhysicsWorld, probes: Int) raises:
    assert_equal(world.contact_count, probes)
    for i in range(1, len(world.bodies)):
        assert_true(world.bodies[i].position.z >= 0.09999)


def _complete(
    name: String,
    side: Int,
    probes: Int,
    rays: Int,
    distribution: Int,
    mut meter: _Meter,
) raises:
    var brute = _make(side, probes, distribution, True)
    var indexed = _make(side, probes, distribution, False)
    _reset_scene(brute, distribution)
    _reset_scene(indexed, distribution)
    # This single cold step is also the one required warmup for each path.
    meter.begin()
    brute.step(Duration(0.01))
    var brute_cold = meter.end()
    _report(name, brute, probes, rays, "cold_warmup_step", -1, brute_cold)
    meter.begin()
    indexed.step(Duration(0.01))
    var indexed_cold = meter.end()
    _report(name, indexed, probes, rays, "cold_warmup_step", -1, indexed_cold)
    _assert_stopped(brute, probes)
    _assert_saved(indexed, _save(brute))
    assert_equal(_retained(brute), 0)
    assert_equal(indexed._ccd_index.count, len(indexed._triangles))
    if len(indexed._triangles) <= 8:
        assert_equal(_retained(indexed), 0)
    else:
        assert_equal(
            len(indexed._ccd_index.nodes), 2 * len(indexed._triangles) - 1
        )
    var brute_ns = 0
    var indexed_ns = 0
    var brute_max = 0
    var indexed_max = 0
    var brute_peak = UInt64(0)
    var indexed_peak = UInt64(0)
    var brute_total = UInt64(0)
    var indexed_total = UInt64(0)
    var brute_calls = UInt64(0)
    var indexed_calls = UInt64(0)
    var brute_ray_ns = 0
    var indexed_ray_ns = 0
    var brute_checksum = Float64(0)
    var indexed_checksum = Float64(0)
    for repetition in range(20):
        _reset_scene(brute, distribution)
        _reset_scene(indexed, distribution)
        var b: Tuple[Int, UInt64, UInt64, UInt64]
        var a: Tuple[Int, UInt64, UInt64, UInt64]
        if repetition % 2 == 0:
            meter.begin()
            brute.step(Duration(0.01))
            b = meter.end()
            meter.begin()
            indexed.step(Duration(0.01))
            a = meter.end()
        else:
            meter.begin()
            indexed.step(Duration(0.01))
            a = meter.end()
            meter.begin()
            brute.step(Duration(0.01))
            b = meter.end()
        _report(name, brute, probes, rays, "complete_step", repetition, b)
        _report(name, indexed, probes, rays, "complete_step", repetition, a)
        _assert_stopped(brute, probes)
        _assert_saved(indexed, _save(brute))
        brute_ns += b[0]
        indexed_ns += a[0]
        brute_max = max(brute_max, b[0])
        indexed_max = max(indexed_max, a[0])
        brute_peak = max(brute_peak, b[1])
        indexed_peak = max(indexed_peak, a[1])
        brute_total += b[2]
        indexed_total += a[2]
        brute_calls += b[3]
        indexed_calls += a[3]
        var bc: Float64
        var ac: Float64
        if repetition % 2 == 0:
            meter.begin()
            bc = _ray_batch(brute, side, rays, distribution)
            b = meter.end()
            meter.begin()
            ac = _ray_batch(indexed, side, rays, distribution)
            a = meter.end()
        else:
            meter.begin()
            ac = _ray_batch(indexed, side, rays, distribution)
            a = meter.end()
            meter.begin()
            bc = _ray_batch(brute, side, rays, distribution)
            b = meter.end()
        _report(name, brute, probes, rays, "ray_batch", repetition, b, bc)
        _report(name, indexed, probes, rays, "ray_batch", repetition, a, ac)
        assert_equal(ac, bc)
        if distribution == 0:
            assert_equal(bc, Float64(5 * rays))
        brute_ray_ns += b[0]
        indexed_ray_ns += a[0]
        brute_checksum += bc
        indexed_checksum += ac
    _report(
        name,
        brute,
        probes,
        rays,
        "mean_complete_step",
        20,
        (brute_ns // 20, brute_peak, brute_total // 20, brute_calls // 20),
    )
    _report(
        name,
        indexed,
        probes,
        rays,
        "mean_complete_step",
        20,
        (
            indexed_ns // 20,
            indexed_peak,
            indexed_total // 20,
            indexed_calls // 20,
        ),
    )
    _report(
        name,
        brute,
        probes,
        rays,
        "max_complete_step",
        20,
        (brute_max, UInt64(0), UInt64(0), UInt64(0)),
    )
    _report(
        name,
        indexed,
        probes,
        rays,
        "max_complete_step",
        20,
        (indexed_max, UInt64(0), UInt64(0), UInt64(0)),
    )
    _report(
        name,
        brute,
        probes,
        rays,
        "mean_ray_batch_and_total_checksum",
        20,
        (brute_ray_ns // 20, UInt64(0), UInt64(0), UInt64(0)),
        brute_checksum,
    )
    _report(
        name,
        indexed,
        probes,
        rays,
        "mean_ray_batch_and_total_checksum",
        20,
        (indexed_ray_ns // 20, UInt64(0), UInt64(0), UInt64(0)),
        indexed_checksum,
    )
    if distribution == 0:
        assert_equal(brute_checksum, Float64(100 * rays))
    assert_equal(indexed_checksum, brute_checksum)
    for lifetime in [1, 2, 5, 20, 100, 1000]:
        _report(
            name,
            brute,
            probes,
            rays,
            "estimated_amortized_step",
            lifetime,
            (
                Int(
                    (brute_cold[0] + (lifetime - 1) * (brute_ns // 20))
                    // lifetime
                ),
                UInt64(0),
                UInt64(0),
                UInt64(0),
            ),
        )
        _report(
            name,
            indexed,
            probes,
            rays,
            "estimated_amortized_step",
            lifetime,
            (
                Int(
                    (indexed_cold[0] + (lifetime - 1) * (indexed_ns // 20))
                    // lifetime
                ),
                UInt64(0),
                UInt64(0),
                UInt64(0),
            ),
        )


def _order(mut impacts: List[_CCDImpact]):
    # Exact order-only replay of PhysicsWorld._ccd_positions.
    for i in range(1, len(impacts)):
        var j = i
        while j > 0 and impacts[j - 1].time > impacts[j].time:
            impacts.swap_elements(j - 1, j)
            j -= 1


def _phases(
    name: String,
    side: Int,
    probes: Int,
    rays: Int,
    distribution: Int,
    brute: Bool,
    mut meter: _Meter,
) raises:
    var world = _make(side, probes, distribution, brute)
    _reset_scene(world, distribution)
    meter.begin()
    world._validate_ccd()
    var measured = meter.end()
    _report(
        name,
        world,
        probes,
        rays,
        "first_geometry_validation_cache",
        -1,
        measured,
    )
    meter.begin()
    world._ccd_separation(0.01)
    measured = meter.end()
    _report(name, world, probes, rays, "first_domain_separation", -1, measured)
    if not brute:
        # Fresh standalone storage isolates build scratch from geometry checks.
        var cache = _CCDIndex()
        meter.begin()
        cache.rebuild(world._triangles)
        measured = meter.end()
        assert_equal(cache.nodes.capacity(), world._ccd_index.nodes.capacity())
        _report(
            name, world, probes, rays, "fresh_index_build_only", -1, measured
        )
    if distribution == 2 and not brute:
        var candidates = List[Int]()
        _ = world._ccd_index.query(
            _wide(world.bodies[1].position),
            _wide(world.bodies[1].linear_velocity) * Float64(Float32(0.01)),
            Float64(world.bodies[1].shape.radius),
            candidates,
        )
        assert_equal(len(candidates), 2048)
        assert_equal(len(candidates), len(world._triangles))
    world.step(Duration(0.01))
    _reset_scene(world, distribution)
    var baseline = _save(world)
    for repetition in range(20):
        _restore(world, baseline)
        meter.begin()
        for body in world.bodies:
            body.validate()
        assert_true(world.collision_detection.is_valid())
        world._validate_ccd()
        measured = meter.end()
        _report(
            name, world, probes, rays, "warm_validation", repetition, measured
        )

        meter.begin()
        var transaction = _save(world)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "transaction_snapshot",
            repetition,
            measured,
            Float64(len(transaction.bodies)),
        )
        meter.begin()
        world._ccd_separation(0.01)
        measured = meter.end()
        _report(
            name, world, probes, rays, "separation_domain", repetition, measured
        )

        _restore(world, baseline)
        meter.begin()
        var impacts = List[_CCDImpact]()
        var checksum = Float64(0)
        for i in range(1, len(world.bodies)):
            var result = world._ccd_sphere(i, 0.01, impacts)
            checksum += Float64(result[0].z)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "swept_query_exact_solve_response",
            repetition,
            measured,
            checksum,
        )
        assert_equal(len(impacts), probes)
        meter.begin()
        _order(impacts)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "event_order_only_replay",
            repetition,
            measured,
            Float64(len(impacts)),
        )
        for i in range(1, len(impacts)):
            assert_true(impacts[i - 1].time <= impacts[i].time)
        # Read actual sorted identities so ordering cannot be dead work.
        for i in range(len(impacts)):
            assert_equal(impacts[i].body, i + 1)

        # Same record count, but a separate synthetic descending-time input.
        # Keep all preparation and output checks out of this ordering timer.
        var descending = impacts.copy()
        for i in range(len(descending)):
            descending[i].time = Float64(len(descending) - i) * 0.000001
        meter.begin()
        _order(descending)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "event_order_descending_synthetic",
            repetition,
            measured,
            Float64(len(descending)),
        )
        for i in range(len(descending)):
            assert_equal(descending[i].body, len(descending) - i)
            if i > 0:
                assert_true(descending[i - 1].time < descending[i].time)

        _restore(world, baseline)
        meter.begin()
        var positions = world._ccd_positions(0.01)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "positions_separation_query_order",
            repetition,
            measured,
            Float64(len(positions)),
        )
        assert_equal(len(positions), probes)
        # This diagnostic measures the restoration operations themselves.
        # Actual exhausted-step rollback is measured in a separate fixture.
        meter.begin()
        _restore(world, baseline)
        measured = meter.end()
        _report(
            name,
            world,
            probes,
            rays,
            "restore_copy_replay",
            repetition,
            measured,
        )
        _assert_saved(world, baseline)


def _rollback_world(brute: Bool) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    var triangles = List[Triangle]()
    triangles.append(
        Triangle(
            Vector3(-100, -100, 0), Vector3(100, -100, 0), Vector3(0, 100, 0)
        )
    )
    triangles.append(
        Triangle(
            Vector3(-100, -100, 1), Vector3(0, 100, 1), Vector3(100, -100, 1)
        )
    )
    # Distant faces activate the index without duplicating the bounce faces
    # throughout the unrelated existing contact octree.
    for i in range(62):
        var a = Vector3(Float32(256 + i * 4), 0, 0)
        triangles.append(
            Triangle(a, a + Vector3(2, 0, 0), a + Vector3(0, 2, 0))
        )
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(triangles^),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    var ball = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 0.5),
        Quaternion.identity(),
    )
    ball.material = PhysicsMaterial(0, 1)
    ball.linear_velocity = Vector3(0, 0, -300)
    _ = world.add_body(ball^)
    return world^


def _failure(mut world: PhysicsWorld) raises:
    var exhausted = False
    try:
        world.step(Duration(0.01))
    except error:
        exhausted = "CCD impact limit exhausted" in String(error)
    assert_true(exhausted)


def _rollback(brute: Bool, mut meter: _Meter) raises:
    var world = _rollback_world(brute)
    # One successful warmup confirms the fixture needs four impacts.
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 4)
    world.bodies[1].position = Vector3(0, 0, 0.5)
    world.bodies[1].linear_velocity = Vector3(0, 0, -300)
    world.bodies[1].force = Vector3(1, 2, 3)
    world.ccd_max_impacts = 3
    var saved = _save(world)
    for repetition in range(20):
        meter.begin()
        _failure(world)
        var measured = meter.end()
        _report(
            "impact-exhaustion",
            world,
            1,
            0,
            "failed_step_with_rollback",
            repetition,
            measured,
        )
        _assert_saved(world, saved)


def _run(
    name: String,
    side: Int,
    probes: Int,
    rays: Int,
    distribution: Int,
    mut meter: _Meter,
) raises:
    _complete(name, side, probes, rays, distribution, meter)
    _phases(name, side, probes, rays, distribution, True, meter)
    _phases(name, side, probes, rays, distribution, False, meter)


def main() raises:
    """Print native timings or separately hooked allocation diagnostics."""
    var args = argv()
    var hook = String(args[1]) if len(args) > 1 else String("")
    var meter = _Meter(hook)
    print(
        "scene,mode,phase,triangles,spheres,rays,repetition,ns,peak_requested_bytes,total_requested_bytes,allocation_calls,retained_index_bytes,checksum"
    )
    # Keep these workload sizes and repeat counts unchanged.
    _run("vehicle-probe", 32, 1, 64, 0, meter)
    _run("separated-fleet", 64, 32, 256, 0, meter)
    _run("sensor-scale", 128, 16, 2048, 0, meter)
    _run("small-fallback", 2, 1, 64, 0, meter)
    _run("clustered", 32, 16, 256, 1, meter)
    _run("worst-initial-overlap", 32, 1, 256, 2, meter)
    _rollback(True, meter)
    _rollback(False, meter)
