# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure owned frozen rays against the complete issue 288 corpus.

Run native timing and allocation-hook measurements separately. Build the hook
from physics_snapshot_allocations.c. Zero memory counters in a native run
mean unmeasured, not allocation-free. The hook reports requested Mojo bytes
on one query thread, excluding allocator metadata and RSS. The live column
is allocations made in this phase that remain live when the phase ends.

World generation, ray generation, warmups, exact answer checks, and source
mutation occur outside measured phases. Timed ray batches consume answers
in a checksum and do not retain output arrays. Every timed answer is also
checked exactly outside timing. Native query order rotates through all four paths. Build and batch rows are independently measured; amortized
costs derived from them are estimates, not observed end-to-end latency.

The dynamic-participant sweep is a benchmark control, not contact integration.
It retains the original oriented predicate and single pair emission. Refit
probes exercise only the shared primitive index; a frozen public snapshot is
never changed by refit or by mutation of its source world.
"""

from bench.physics_static_bench import (
    _Meter,
    _position,
    _snapshot,
    _sweep,
    _sweep_order,
    _world,
)
from bench.physics_static_bvh import _SnapshotBVH, _Node
from extensions.physics.body import BodyId
from extensions.physics.query_snapshot import (
    PhysicsQuerySnapshot,
    SnapshotRaycastHit,
    SnapshotOwner,
)
from extensions.physics.world import PhysicsWorld, RaycastHit, _box_of
from extensions.physics.collide import WorldShape
from extensions.physics.shape import PhysicsMaterial, _finite_vector
from math.octree import _OctreeNode
from math.triangle import Triangle
from math.bounds import Box3
from math.ray import Ray
from math.sort_utils import stable_sort
from math.vector3 import Vector3
from std.math import inf
from std.sys import argv, size_of
from std.testing import assert_equal, assert_true
from units.si import Length


def _less(a: Int, b: Int) -> Bool:
    return a < b


def _finish(meter: _Meter) raises -> Tuple[Int, UInt64, UInt64, UInt64, UInt64]:
    var measured = meter.end()
    var live = UInt64(0)
    if meter.hooked:
        live = meter.library.call["physics_snapshot_allocations_live", UInt64]()
    return (measured[0], measured[1], measured[2], measured[3], live)


def _report(
    measured: Tuple[Int, UInt64, UInt64, UInt64, UInt64],
    group: String,
    phase: String,
    n: Int,
    moving: Int,
    distribution: Int,
    repetition: Int,
    work: Int = 0,
    pairs: Int = 0,
    checksum: Float64 = 0,
    geometry_bytes: Int = 0,
    index_bytes: Int = 0,
    metadata_bytes: Int = 0,
):
    print(
        group,
        phase,
        n,
        moving,
        distribution,
        repetition,
        measured[0],
        measured[1],
        measured[2],
        measured[3],
        measured[4],
        work,
        pairs,
        checksum,
        geometry_bytes,
        index_bytes,
        metadata_bytes,
        sep=",",
    )


def _retained(snapshot: PhysicsQuerySnapshot) -> Tuple[Int, Int, Int]:
    # Payload capacities, including nested owned geometry. This is not RSS,
    # and excludes inline headers plus the capture token's allocator header.
    var geometry = snapshot._shapes.capacity() * size_of[WorldShape]()
    for shape in snapshot._shapes:
        ref poly = shape.polyhedron
        geometry += (
            poly.vertices.capacity() + poly.normals.capacity()
        ) * size_of[Vector3]()
        geometry += poly.offsets.capacity() * size_of[Float32]()
        geometry += (
            poly.face_start.capacity()
            + poly.face_corners.capacity()
            + poly.edge_a.capacity()
            + poly.edge_b.capacity()
        ) * size_of[Int]()
    geometry += (
        snapshot._triangles.capacity() + snapshot._octree.triangles.capacity()
    ) * size_of[Triangle]()
    var index = snapshot._octree._nodes.capacity() * size_of[_OctreeNode]()
    index += snapshot._boxes.capacity() * size_of[Box3]()
    index += _retained_index(snapshot._index)
    for node in snapshot._octree._nodes:
        index += (
            node.triangles.capacity() + node.sub_trees.capacity()
        ) * size_of[Int]()
    var metadata = (
        snapshot._owners.capacity() + snapshot._triangle_body.capacity()
    ) * size_of[Int]()
    metadata += snapshot._materials.capacity() * size_of[PhysicsMaterial]()
    metadata += snapshot._enabled.capacity() * size_of[Bool]()
    metadata += (
        snapshot._index_entries.capacity() + snapshot._safe_axes.capacity()
    ) * size_of[Int]()
    metadata += snapshot._axis_linear.capacity() * size_of[List[Int]]()
    for linear in snapshot._axis_linear:
        metadata += linear.capacity() * size_of[Int]()
    return (geometry, index, metadata)


def _retained_index(tree: _SnapshotBVH) -> Int:
    return (
        tree.nodes.capacity() * size_of[_Node]()
        + tree.boxes.capacity() * size_of[Box3]()
        + (tree.order.capacity() + tree.buffer.capacity()) * size_of[Int]()
    )


def _index(snapshot: PhysicsQuerySnapshot) raises -> _SnapshotBVH:
    var boxes = List[Box3](capacity=len(snapshot._shapes))
    for shape in snapshot._shapes:
        boxes.append(_box_of(shape))
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    return tree^


def _indexed_ray(
    snapshot: PhysicsQuerySnapshot,
    tree: _SnapshotBVH,
    source_ray: Ray,
    mut found: List[Int],
) raises -> Optional[SnapshotRaycastHit]:
    # Same finite-input checks, Ray reconstruction, and owned result as the
    # public frozen-linear call. The only changed work is primitive culling.
    _finite_vector(source_ray.origin)
    _finite_vector(source_ray.direction)
    var ray = Ray(source_ray.origin, source_ray.direction)
    var best = snapshot._mesh_hit(ray, 1000, BodyId(-1))
    _ = tree.ray(ray, found)
    stable_sort[_less](found)
    for entry in found:
        var hit = snapshot._shape_hit(ray, entry)
        if not hit:
            continue
        var value = hit.value()
        if value.distance > 1000:
            continue
        if best and best.value().distance <= value.distance:
            continue
        best = value
    if not best:
        return None
    var hit = best.value()
    return SnapshotRaycastHit(
        SnapshotOwner(hit.body, snapshot._capture),
        hit.point,
        hit.normal,
        Length(hit.distance),
        hit.material,
    )


def _indexed_batch(
    snapshot: PhysicsQuerySnapshot, tree: _SnapshotBVH, rays: List[Ray]
) raises -> Float64:
    var checksum = Float64(0)
    var found = List[Int]()
    for ray in rays:
        var hit = _indexed_ray(snapshot, tree, ray, found)
        if hit:
            checksum += Float64(
                hit.value().owner.source_body.value + 1
            ) + Float64(hit.value().distance.value)
    return checksum


def _check_index(
    snapshot: PhysicsQuerySnapshot,
    tree: _SnapshotBVH,
    rays: List[Ray],
    expected: List[Optional[RaycastHit]],
) raises:
    var found = List[Int]()
    for i in range(len(rays)):
        _equal(_indexed_ray(snapshot, tree, rays[i], found), expected[i])


def _rays(n: Int, distribution: Int) raises -> List[Ray]:
    var rays = List[Ray](capacity=1024)
    for i in range(1024):
        var target = _position((i * 37) % max(n, 1), distribution)
        if i % 4 == 0:
            target.y += 2
        rays.append(Ray(target + Vector3(-10, 0, 0), Vector3(1, 0, 0)))
    return rays^


def _linear_batch(world: PhysicsWorld, rays: List[Ray]) raises -> Float64:
    var checksum = Float64(0)
    for ray in rays:
        var hit = world.raycast(
            ray.origin, ray.direction, Length(1000), BodyId(-1)
        )
        if hit:
            checksum += Float64(hit.value().body.value + 1) + Float64(
                hit.value().distance
            )
    return checksum


def _frozen_linear_ray(
    snapshot: PhysicsQuerySnapshot, source_ray: Ray
) raises -> Optional[SnapshotRaycastHit]:
    # Control: the same owned geometry and result identity, without candidate
    # selection. Fixed reach/ignore checks match the timed public call.
    _finite_vector(source_ray.origin)
    _finite_vector(source_ray.direction)
    var ray = Ray(source_ray.origin, source_ray.direction)
    return snapshot._owned_hit(snapshot._linear_hit(ray, 1000, BodyId(-1)))


def _frozen_linear_batch(
    snapshot: PhysicsQuerySnapshot, rays: List[Ray]
) raises -> Float64:
    var checksum = Float64(0)
    for ray in rays:
        var hit = _frozen_linear_ray(snapshot, ray)
        if hit:
            checksum += Float64(
                hit.value().owner.source_body.value + 1
            ) + Float64(hit.value().distance.value)
    return checksum


def _snapshot_batch(
    snapshot: PhysicsQuerySnapshot, rays: List[Ray]
) raises -> Float64:
    var checksum = Float64(0)
    for ray in rays:
        var hit = snapshot.raycast(
            ray.origin, ray.direction, Length(1000), BodyId(-1)
        )
        if hit:
            checksum += Float64(
                hit.value().owner.source_body.value + 1
            ) + Float64(hit.value().distance.value)
    return checksum


def _equal(
    actual: Optional[SnapshotRaycastHit], expected: Optional[RaycastHit]
) raises:
    assert_equal(Bool(actual), Bool(expected))
    if expected:
        assert_equal(actual.value().owner.source_body, expected.value().body)
        assert_equal(actual.value().distance.value, expected.value().distance)
        assert_true(actual.value().point == expected.value().point)
        assert_true(actual.value().normal == expected.value().normal)
        assert_equal(
            actual.value().material.friction, expected.value().material.friction
        )
        assert_equal(
            actual.value().material.restitution,
            expected.value().material.restitution,
        )


def _expected(
    world: PhysicsWorld, rays: List[Ray]
) raises -> List[Optional[RaycastHit]]:
    var expected = List[Optional[RaycastHit]](capacity=len(rays))
    for ray in rays:
        expected.append(
            world.raycast(ray.origin, ray.direction, Length(1000), BodyId(-1))
        )
    return expected^


def _check(
    snapshot: PhysicsQuerySnapshot,
    rays: List[Ray],
    expected: List[Optional[RaycastHit]],
) raises:
    for i in range(len(rays)):
        _equal(_frozen_linear_ray(snapshot, rays[i]), expected[i])
        _equal(
            snapshot.raycast(
                rays[i].origin, rays[i].direction, Length(1000), BodyId(-1)
            ),
            expected[i],
        )


def _dynamic_prepare(
    world: PhysicsWorld,
    boxes: List[Box3],
    owners: List[Int],
    order: List[Int],
) -> Tuple[List[Float32], List[Int]]:
    var prefix = List[Float32](capacity=len(order))
    var dynamic = List[Int]()
    var far = -inf[DType.float32]()
    for rank in range(len(order)):
        var entry = order[rank]
        far = max(far, boxes[entry].max.x + world.margin)
        prefix.append(far)
        if world.bodies[owners[entry]].is_dynamic():
            dynamic.append(rank)
    return (prefix^, dynamic^)


def _dynamic_query(
    world: PhysicsWorld,
    boxes: List[Box3],
    owners: List[Int],
    order: List[Int],
    prefix: List[Float32],
    dynamic: List[Int],
    mut keys: List[Int],
) -> Tuple[Int, Int, Int]:
    keys.clear()
    var visited = 0
    var pairs = 0
    var checksum = 0
    for rank in dynamic:
        var a = order[rank]
        # First earlier entry whose prefix can reach a. Values use the
        # original Float32 max.x + margin, preserving the sweep's cutoff.
        var low = 0
        var high = rank
        while low < high:
            var middle = low + (high - low) // 2
            if prefix[middle] < boxes[a].min.x:
                low = middle + 1
            else:
                high = middle
        for other in range(low, len(order)):
            var b = order[other]
            if other > rank and boxes[b].min.x > boxes[a].max.x + world.margin:
                break
            visited += 1
            if other == rank:
                continue
            if other < rank and world.bodies[owners[b]].is_dynamic():
                continue
            var first = b if other < rank else a
            var second = a if other < rank else b
            if boxes[second].min.x > boxes[first].max.x + world.margin:
                continue
            var grown = boxes[first]
            grown.expand_by_scalar(world.margin)
            if grown.intersects_box(boxes[second]):
                pairs += 1
                checksum += min(a, b) * len(boxes) + max(a, b)
                keys.append(min(rank, other) * len(boxes) + max(rank, other))
    stable_sort[_less](keys)
    return (visited, pairs, checksum)


def _sweep_keys(
    world: PhysicsWorld, boxes: List[Box3], owners: List[Int], order: List[Int]
) -> List[Int]:
    var keys = List[Int]()
    for rank in range(len(order)):
        var a = order[rank]
        for other in range(rank + 1, len(order)):
            var b = order[other]
            if boxes[b].min.x > boxes[a].max.x + world.margin:
                break
            if not (
                world.bodies[owners[a]].is_dynamic()
                or world.bodies[owners[b]].is_dynamic()
            ):
                continue
            var grown = boxes[a]
            grown.expand_by_scalar(world.margin)
            if grown.intersects_box(boxes[b]):
                keys.append(rank * len(boxes) + other)
    return keys^


def _measure_sweep(
    world: PhysicsWorld,
    n: Int,
    moving: Int,
    distribution: Int,
    repetition: Int,
    mut meter: _Meter,
) raises:
    var stored = _snapshot(world)
    var boxes = stored[0].copy()
    var owners = stored[1].copy()
    var order = List[Int]()
    for i in range(len(boxes)):
        order.append(i)
    _sweep_order(boxes, order)
    meter.begin()
    var expected = _sweep(world, boxes, owners, order)
    _report(
        _finish(meter),
        "corpus",
        "sweep_query",
        n,
        moving,
        distribution,
        repetition,
        expected[0],
        expected[1],
        Float64(expected[2]),
    )
    meter.begin()
    var prepared = _dynamic_prepare(world, boxes, owners, order)
    _report(
        _finish(meter),
        "corpus",
        "dynamic_prepare",
        n,
        moving,
        distribution,
        repetition,
        len(order),
        len(prepared[1]),
    )
    var keys = List[Int]()
    meter.begin()
    var actual = _dynamic_query(
        world, boxes, owners, order, prepared[0], prepared[1], keys
    )
    _report(
        _finish(meter),
        "corpus",
        "dynamic_query",
        n,
        moving,
        distribution,
        repetition,
        actual[0],
        actual[1],
        Float64(actual[2]),
    )
    assert_equal(actual[1], expected[1])
    assert_equal(actual[2], expected[2])
    assert_equal(keys, _sweep_keys(world, boxes, owners, order))


def _measure_rays(
    world: PhysicsWorld,
    snapshot: PhysicsQuerySnapshot,
    tree: _SnapshotBVH,
    rays: List[Ray],
    group: String,
    n: Int,
    moving: Int,
    distribution: Int,
    repetition: Int,
    mut meter: _Meter,
) raises:
    var linear = Float64(0)
    var frozen = Float64(0)
    var captured = Float64(0)
    var indexed = Float64(0)
    for path in range(4):
        if (path + repetition) % 4 == 0:
            meter.begin()
            linear = _linear_batch(world, rays)
            _report(
                _finish(meter),
                group,
                "ray_linear_1024",
                n,
                moving,
                distribution,
                repetition,
                len(rays),
                0,
                linear,
            )
        elif (path + repetition) % 4 == 1:
            meter.begin()
            frozen = _frozen_linear_batch(snapshot, rays)
            _report(
                _finish(meter),
                group,
                "ray_frozen_linear_1024",
                n,
                moving,
                distribution,
                repetition,
                len(rays),
                0,
                frozen,
            )
        elif (path + repetition) % 4 == 2:
            meter.begin()
            captured = _snapshot_batch(snapshot, rays)
            _report(
                _finish(meter),
                group,
                "ray_snapshot_1024",
                n,
                moving,
                distribution,
                repetition,
                len(rays),
                0,
                captured,
            )
        else:
            meter.begin()
            indexed = _indexed_batch(snapshot, tree, rays)
            _report(
                _finish(meter),
                group,
                "ray_forced_index_1024",
                n,
                moving,
                distribution,
                repetition,
                len(rays),
                0,
                indexed,
            )
    assert_equal(linear, frozen)
    assert_equal(linear, captured)
    assert_equal(linear, indexed)


def _measure(
    n: Int,
    moving: Int,
    distribution: Int,
    mut meter: _Meter,
    repeats: Int,
) raises:
    var world = _world(n, moving, distribution)
    var rays = _rays(n, distribution)
    for repetition in range(repeats):
        # Identical one-centimeter alternating states to the issue 288 corpus.
        for i in range(moving):
            world.bodies[n + i].position = _position(
                (i * 97) % n, distribution
            ) + Vector3(
                0.99, Float32(0.01) if repetition % 2 == 0 else Float32(0), 0
            )
        _measure_sweep(world, n, moving, distribution, repetition, meter)
        meter.begin()
        var snapshot = PhysicsQuerySnapshot(world)
        var measured = _finish(meter)
        var retained = _retained(snapshot)
        _report(
            measured,
            "corpus",
            "snapshot_build",
            n,
            moving,
            distribution,
            repetition,
            n + moving,
            len(snapshot._index_entries),
            0,
            retained[0],
            retained[1],
            retained[2],
        )
        meter.begin()
        var tree = _index(snapshot)
        measured = _finish(meter)
        _report(
            measured,
            "corpus",
            "forced_index_build",
            n,
            moving,
            distribution,
            repetition,
            len(tree.nodes),
            0,
            0,
            0,
            _retained_index(tree),
        )
        if moving != 10:
            continue
        var expected = _expected(world, rays)
        _check(snapshot, rays, expected)
        _check_index(snapshot, tree, rays, expected)
        _ = _frozen_linear_batch(snapshot, rays)
        _ = _snapshot_batch(snapshot, rays)
        _ = _indexed_batch(snapshot, tree, rays)
        _measure_rays(
            world,
            snapshot,
            tree,
            rays,
            "corpus",
            n,
            moving,
            distribution,
            repetition,
            meter,
        )
        if repetition == repeats - 1:
            # Change each source pose, material and enable bit. Retained
            # answers must remain exact both now and after source destruction.
            for i in range(len(world.bodies)):
                world.bodies[i].position = Vector3(100000, 100000, 100000)
                world.bodies[i].material.friction = 0
                world.bodies[i].collides = False
            _check(snapshot, rays, expected)
            world = PhysicsWorld()
            meter.begin()
            var checksum = _snapshot_batch(snapshot, rays)
            _report(
                _finish(meter),
                "corpus",
                "frozen_after_release_1024",
                n,
                moving,
                distribution,
                repetition,
                len(rays),
                0,
                checksum,
            )
            _check(snapshot, rays, expected)


def _measure_small(
    n: Int, distribution: Int, mut meter: _Meter, repeats: Int
) raises:
    var world = _world(n, 0, distribution)
    var rays = _rays(n, distribution)
    var expected = _expected(world, rays)
    for repetition in range(repeats):
        meter.begin()
        var snapshot = PhysicsQuerySnapshot(world)
        var measured = _finish(meter)
        var retained = _retained(snapshot)
        _report(
            measured,
            "small",
            "snapshot_build",
            n,
            0,
            distribution,
            repetition,
            n,
            len(snapshot._index_entries),
            0,
            retained[0],
            retained[1],
            retained[2],
        )
        meter.begin()
        var tree = _index(snapshot)
        measured = _finish(meter)
        _report(
            measured,
            "small",
            "forced_index_build",
            n,
            0,
            distribution,
            repetition,
            len(tree.nodes),
            0,
            0,
            0,
            _retained_index(tree),
        )
        _check(snapshot, rays, expected)
        _check_index(snapshot, tree, rays, expected)
        _ = _linear_batch(world, rays)
        _ = _frozen_linear_batch(snapshot, rays)
        _ = _snapshot_batch(snapshot, rays)
        _ = _indexed_batch(snapshot, tree, rays)
        _measure_rays(
            world,
            snapshot,
            tree,
            rays,
            "small",
            n,
            0,
            distribution,
            repetition,
            meter,
        )


def _tree_batch(tree: _SnapshotBVH, rays: List[Ray]) -> Tuple[Int, Int, Int]:
    var found = List[Int]()
    var work = 0
    var candidates = 0
    var checksum = 0
    for ray in rays:
        work += tree.ray(ray, found)
        candidates += len(found)
        for entry in found:
            checksum += entry + 1
    return (work, candidates, checksum)


def _check_tree(a: _SnapshotBVH, b: _SnapshotBVH, rays: List[Ray]) raises:
    var first = List[Int]()
    var second = List[Int]()
    for ray in rays:
        _ = a.ray(ray, first)
        _ = b.ray(ray, second)
        stable_sort[_less](first)
        stable_sort[_less](second)
        assert_equal(first, second)


def _measure_refit(
    n: Int, percent: Int, mut meter: _Meter, repeats: Int
) raises:
    var world = _world(n, 0, 0)
    var stored = _snapshot(world)
    var original = stored[0].copy()
    var changed = original.copy()
    for i in range(n * percent // 100):
        changed[i] = original[(i * 37) % n]
    var rays = _rays(n, 0)
    for repetition in range(repeats):
        var refitted = _SnapshotBVH()
        refitted.rebuild(original)
        meter.begin()
        refitted.refit(changed)
        _report(
            _finish(meter),
            "refit",
            "index_refit",
            n,
            percent,
            0,
            repetition,
            len(refitted.nodes),
        )
        var rebuilt = _SnapshotBVH()
        meter.begin()
        rebuilt.rebuild(changed)
        _report(
            _finish(meter),
            "refit",
            "index_rebuild",
            n,
            percent,
            0,
            repetition,
            len(rebuilt.nodes),
        )
        _check_tree(refitted, rebuilt, rays)
        for path in range(2):
            if (path + repetition) % 2 == 0:
                meter.begin()
                var result = _tree_batch(refitted, rays)
                _report(
                    _finish(meter),
                    "refit",
                    "refit_ray_1024",
                    n,
                    percent,
                    0,
                    repetition,
                    result[0],
                    result[1],
                    Float64(result[2]),
                )
            else:
                meter.begin()
                var result = _tree_batch(rebuilt, rays)
                _report(
                    _finish(meter),
                    "refit",
                    "rebuilt_ray_1024",
                    n,
                    percent,
                    0,
                    repetition,
                    result[0],
                    result[1],
                    Float64(result[2]),
                )


def main() raises:
    """Print the complete corpus, small-world and refit probes.

    The optional first process argument names the allocation hook.
    CSV rows are written to standard output.

    Raises:
        Error: If construction, allocation-hook checks or exact parity fails.
    """
    var args = argv()
    var hook = String(args[1]) if len(args) > 1 else String("")
    var meter = _Meter(hook)
    var repeats = 1 if hook else 3
    print(
        "group,phase,static,moving,distribution,repetition,ns,peak_bytes,total_bytes,allocations,live_bytes,work,pairs,checksum,geometry_bytes,index_bytes,metadata_bytes"
    )
    for count in [100, 1000, 10000]:
        for distribution in range(4):
            for moving in [1, 10, 100]:
                _measure(count, moving, distribution, meter, repeats)
    for count in [0, 1, 4, 8, 16, 32, 64]:
        for distribution in range(4):
            _measure_small(count, distribution, meter, repeats)
    for count in [100, 1000, 10000]:
        for percent in [0, 25, 50, 100]:
            _measure_refit(count, percent, meter, repeats)
