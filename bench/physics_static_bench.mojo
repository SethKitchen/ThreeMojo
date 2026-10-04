# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare a rebuilt primitive snapshot BVH with the main sweep and ray loop.

Run without arguments for native timings. For allocation counts, preload
bench/navigation_allocations.c and pass the same shared library path.
Hooked timings are diagnostic only. Every row reports one complete phase.
"""

from bench.physics_static_bvh import _SnapshotBVH
from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.physics.shape import MESH, Shape
from extensions.physics.collide import WorldShape, collide
from extensions.physics.world import (
    PhysicsWorld,
    RaycastHit,
    _Manifold,
    _box_of,
)
from math.bounds import Box3
from math.quaternion import Quaternion
from math.ray import Ray
from math.sort_utils import stable_sort
from math.vector3 import Vector3
from std.ffi import OwnedDLHandle
from std.sys import argv
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from units.si import Length, Mass


def _less(a: Int, b: Int) -> Bool:
    return a < b


def _snapshot(world: PhysicsWorld) -> Tuple[List[Box3], List[Int]]:
    var boxes = List[Box3]()
    var owners = List[Int]()
    for i in range(len(world.bodies)):
        if world.bodies[i].shape.kind != MESH and world.bodies[i].collides:
            boxes.append(_box_of(world._shape(i)))
            owners.append(i)
    return (boxes^, owners^)


def _sweep_order(boxes: List[Box3], mut order: List[Int]):
    # Same stable insertion order and Float32 key as PhysicsWorld._find_contacts.
    for i in range(1, len(order)):
        var j = i
        while j > 0 and boxes[order[j - 1]].min.x > boxes[order[j]].min.x:
            order.swap_elements(j - 1, j)
            j -= 1


def _sweep(
    world: PhysicsWorld, boxes: List[Box3], owners: List[Int], order: List[Int]
) -> Tuple[Int, Int, Int]:
    var visited = 0
    var pairs = 0
    var checksum = 0
    for i in range(len(order)):
        var a = order[i]
        for j in range(i + 1, len(order)):
            var b = order[j]
            visited += 1
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
                pairs += 1
                checksum += min(a, b) * len(boxes) + max(a, b)
    return (visited, pairs, checksum)


def _pair_keys(
    world: PhysicsWorld,
    boxes: List[Box3],
    owners: List[Int],
    tree: _SnapshotBVH,
    order: List[Int],
    mut keys: List[Int],
) -> Int:
    keys.clear()
    var ranks = List[Int](length=len(boxes), fill=0)
    for i in range(len(order)):
        ranks[order[i]] = i
    var found = List[Int]()
    var visited = 0
    for a in range(len(boxes)):
        if not world.bodies[owners[a]].is_dynamic():
            continue
        # Twice the absolute margin is only a conservative query bound.
        # The exact old oriented Float32 expansion is the final predicate.
        var query = boxes[a]
        query.expand_by_scalar(2 * abs(world.margin))
        visited += tree.overlap(query, found)
        for b in found:
            if a == b:
                continue
            if world.bodies[owners[b]].is_dynamic() and b < a:
                continue
            var first = a if ranks[a] < ranks[b] else b
            var second = b if ranks[a] < ranks[b] else a
            var grown = boxes[first]
            grown.expand_by_scalar(world.margin)
            if boxes[second].min.x > boxes[first].max.x + world.margin:
                continue
            if not grown.intersects_box(boxes[second]):
                continue
            keys.append(ranks[first] * len(boxes) + ranks[second])
    stable_sort[_less](keys)
    return visited


def _indexed(
    world: PhysicsWorld,
    boxes: List[Box3],
    owners: List[Int],
    tree: _SnapshotBVH,
    order: List[Int],
) -> Tuple[Int, Int, Int]:
    var keys = List[Int]()
    var visited = _pair_keys(world, boxes, owners, tree, order, keys)
    var checksum = 0
    for key in keys:
        var a = order[key // len(boxes)]
        var b = order[key % len(boxes)]
        checksum += min(a, b) * len(boxes) + max(a, b)
    return (visited, len(keys), checksum)


def _indexed_contacts(mut world: PhysicsWorld) raises -> List[_Manifold]:
    var snapshot = _snapshot(world)
    var boxes = snapshot[0].copy()
    var owners = snapshot[1].copy()
    var entries = List[Int](length=len(world.bodies), fill=-1)
    for i in range(len(owners)):
        entries[owners[i]] = i
    var order = List[Int]()
    var inactive = List[Int]()
    for owner in world._order:
        if world.bodies[owner].collides:
            order.append(entries[owner])
        else:
            inactive.append(owner)
    _sweep_order(boxes, order)
    world._order.clear()
    for entry in order:
        world._order.append(owners[entry])
    for owner in inactive:
        world._order.append(owner)
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    var keys = List[Int]()
    _ = _pair_keys(world, boxes, owners, tree, order, keys)
    var shapes = List[WorldShape]()
    for owner in owners:
        shapes.append(world._shape(owner))
    var out = List[_Manifold]()
    var cursor = 0
    for rank in range(len(order)):
        var a = order[rank]
        while cursor < len(keys) and keys[cursor] // len(order) == rank:
            var b = order[keys[cursor] % len(order)]
            var points = collide(shapes[a], shapes[b], world.margin)
            world._add(out, owners[a], owners[b], points)
            cursor += 1
        world._mesh_pairs(out, owners[a], shapes[a], boxes[a])
    return out^


def _indexed_ray(
    world: PhysicsWorld,
    tree: _SnapshotBVH,
    owners: List[Int],
    ray: Ray,
    reach: Float32,
    ignore: BodyId,
    mut found: List[Int],
) -> Optional[RaycastHit]:
    _ = tree.ray(ray, found)
    # Entries are in body-id order; preserve PhysicsWorld's first tie winner.
    stable_sort[_less](found)
    var best: Optional[RaycastHit] = None
    # Preserve the world's mesh-first tie rule and dirty-octree fallback.
    if world._dirty:
        for t in range(len(world._triangles)):
            best = world._triangle_hit(ray, t, reach, best, ignore)
    elif len(world._triangles) > 0:
        for t in world._octree.ray_triangles(ray):
            best = world._triangle_hit(ray, t, reach, best, ignore)
    for entry in found:
        var i = owners[entry]
        if i == ignore.value:
            continue
        var hit = world._shape_hit(ray, i)
        if not Bool(hit):
            continue
        var value = hit.value()
        if value.distance > reach:
            continue
        if Bool(best) and best.value().distance <= value.distance:
            continue
        best = value
    return best


def _shapes() raises -> List[Shape]:
    var shapes = List[Shape]()
    shapes.append(Shape.sphere(Length(0.5)))
    shapes.append(Shape.box(Length(0.5), Length(0.5), Length(0.5)))
    shapes.append(Shape.capsule(Length(0.5), Length(0.5)))
    shapes.append(
        Shape.convex(
            [
                Vector3(-0.5, -0.5, -0.5),
                Vector3(0.5, -0.5, -0.5),
                Vector3(0.5, 0.5, -0.5),
                Vector3(-0.5, 0.5, -0.5),
                Vector3(-0.5, -0.5, 0.5),
                Vector3(0.5, -0.5, 0.5),
                Vector3(0.5, 0.5, 0.5),
                Vector3(-0.5, 0.5, 0.5),
            ]
        )
    )
    return shapes^


def _position(i: Int, distribution: Int) -> Vector3:
    if distribution == 0:
        return Vector3(Float32(i % 100) * 4, Float32(i // 100) * 4, 0)
    if distribution == 1:
        return Vector3(0, Float32(i % 100) * 4, Float32(i // 100) * 4)
    if distribution == 2:
        return Vector3(
            Float32(i % 10) * 20 + Float32((i // 10) % 10) * 0.2,
            Float32((i // 100) % 10) * 0.2,
            Float32(i // 1000) * 0.2,
        )
    return Vector3(0, 0, 0)


def _world(statics: Int, moving: Int, distribution: Int) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var shapes = _shapes()
    for i in range(statics):
        _ = world.add_body(
            RigidBody(
                STATIC,
                shapes[i % 4].copy(),
                Mass(0),
                _position(i, distribution),
                Quaternion.identity(),
            )
        )
    for i in range(moving):
        var body = RigidBody(
            DYNAMIC,
            shapes[(i + 1) % 4].copy(),
            Mass(1),
            _position((i * 97) % statics, distribution) + Vector3(0.99, 0, 0),
            Quaternion.identity(),
        )
        # One quarter of participants move kinematically. They still answer
        # rays, and only contact a pair with a dynamic participant.
        if i % 4 == 3:
            body.set_kind(KINEMATIC)
        _ = world.add_body(body^)
    return world^


struct _Meter(Movable):
    var library: OwnedDLHandle
    var hooked: Bool
    var start: Int

    def __init__(out self, hook: String) raises:
        self.hooked = Bool(hook)
        self.library = OwnedDLHandle(hook if hook else String("libc.so.6"))
        self.start = 0
        if self.hooked:
            assert_equal(
                self.library.call["navigation_allocations_selftest", UInt64](),
                1,
            )

    def begin(mut self) raises:
        if self.hooked:
            _ = self.library.call["navigation_allocations_begin", UInt64]()
        self.start = perf_counter_ns()

    def end(self) raises -> Tuple[Int, UInt64, UInt64, UInt64]:
        var ns = perf_counter_ns() - self.start
        var peak = UInt64(0)
        var total = UInt64(0)
        var calls = UInt64(0)
        if self.hooked:
            peak = self.library.call["navigation_allocations_end", UInt64]()
            total = self.library.call["navigation_allocations_total", UInt64]()
            calls = self.library.call["navigation_allocations_calls", UInt64]()
            assert_equal(
                self.library.call["navigation_allocations_overflow", UInt64](),
                0,
            )
        return (ns, peak, total, calls)


def _report(
    measured: Tuple[Int, UInt64, UInt64, UInt64],
    phase: String,
    n: Int,
    moving: Int,
    distribution: Int,
    repetition: Int,
    work: Int,
    pairs: Int,
    checksum: Int,
):
    print(
        phase,
        n,
        moving,
        distribution,
        repetition,
        measured[0],
        measured[1],
        measured[2],
        measured[3],
        work,
        pairs,
        checksum,
        sep=",",
    )


def _measure(
    n: Int, moving: Int, distribution: Int, mut meter: _Meter, repeats: Int
) raises:
    var world = _world(n, moving, distribution)
    var snapshot = _snapshot(world)
    var boxes = snapshot[0].copy()
    var owners = snapshot[1].copy()
    var order = List[Int]()
    for i in range(len(boxes)):
        order.append(i)
    _sweep_order(boxes, order)
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    for repetition in range(repeats):
        # One centimeter of motion between measurements; the first and third
        # repetitions share their state, as does the separate allocation run.
        for i in range(moving):
            world.bodies[n + i].position = _position(
                (i * 97) % n, distribution
            ) + Vector3(
                0.99, Float32(0.01) if repetition % 2 == 0 else Float32(0), 0
            )
        meter.begin()
        var updated = _snapshot(world)
        _report(
            meter.end(),
            "bounds",
            n,
            moving,
            distribution,
            repetition,
            len(updated[0]),
            0,
            len(updated[1]),
        )
        boxes = updated[0].copy()
        owners = updated[1].copy()
        meter.begin()
        _sweep_order(boxes, order)
        _report(
            meter.end(),
            "sweep_update",
            n,
            moving,
            distribution,
            repetition,
            len(order),
            0,
            order[0],
        )
        meter.begin()
        var sweep = _sweep(world, boxes, owners, order)
        _report(
            meter.end(),
            "sweep_query",
            n,
            moving,
            distribution,
            repetition,
            sweep[0],
            sweep[1],
            sweep[2],
        )
        meter.begin()
        tree.rebuild(boxes)
        _report(
            meter.end(),
            "bvh_update",
            n,
            moving,
            distribution,
            repetition,
            len(tree.nodes),
            0,
            len(tree.boxes),
        )
        meter.begin()
        tree.refit(boxes)
        _report(
            meter.end(),
            "bvh_refit",
            n,
            moving,
            distribution,
            repetition,
            len(tree.nodes),
            0,
            len(tree.boxes),
        )
        meter.begin()
        var indexed = _indexed(world, boxes, owners, tree, order)
        _report(
            meter.end(),
            "bvh_query",
            n,
            moving,
            distribution,
            repetition,
            indexed[0],
            indexed[1],
            indexed[2],
        )
        assert_equal(sweep[1], indexed[1])
        assert_equal(sweep[2], indexed[2])
    if moving != 10:
        return
    # A 1024-ray scan through fixed directions and spatial offsets. All four
    # primitive kinds occur in both hits and misses. Query answers are exact
    # comparisons, not only a checksum. The reach is 1000 meters.
    var rays = List[Ray]()
    for i in range(1024):
        var target = _position((i * 37) % n, distribution)
        if i % 4 == 0:
            target.y += 2
        rays.append(Ray(target + Vector3(-10, 0, 0), Vector3(1, 0, 0)))
    for repetition in range(repeats):
        var expected = List[Optional[RaycastHit]](capacity=1024)
        meter.begin()
        for ray in rays:
            expected.append(
                world.raycast(
                    ray.origin, ray.direction, Length(1000), BodyId(-1)
                )
            )
        _report(
            meter.end(),
            "ray_linear_1024",
            n,
            moving,
            distribution,
            repetition,
            n * 1024,
            0,
            len(expected),
        )
        var found = List[Int]()
        var actual = List[Optional[RaycastHit]](capacity=1024)
        meter.begin()
        for ray in rays:
            actual.append(
                _indexed_ray(world, tree, owners, ray, 1000, BodyId(-1), found)
            )
        _report(
            meter.end(),
            "ray_bvh_1024",
            n,
            moving,
            distribution,
            repetition,
            len(tree.nodes),
            0,
            len(actual),
        )
        for i in range(len(rays)):
            assert_equal(Bool(actual[i]), Bool(expected[i]))
            if Bool(expected[i]):
                assert_equal(
                    actual[i].value().body.value, expected[i].value().body.value
                )
                assert_equal(
                    actual[i].value().distance, expected[i].value().distance
                )
                assert_true(
                    actual[i].value().point == expected[i].value().point
                )
                assert_true(
                    actual[i].value().normal == expected[i].value().normal
                )


def main() raises:
    """Print native timings, or separate allocation measurements."""
    var args = argv()
    var hook = String(args[1]) if len(args) > 1 else String("")
    var meter = _Meter(hook)
    print(
        "phase,static,moving,distribution,repetition,ns,peak_bytes,total_bytes,allocations,work,pairs,checksum"
    )
    for count in [100, 1000, 10000]:
        for distribution in range(4):
            for moving in [1, 10, 100]:
                _measure(count, moving, distribution, meter, 1 if hook else 3)
