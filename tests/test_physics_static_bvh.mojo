# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Oracle and lifecycle checks for the unadopted static-index prototype."""

from bench.physics_static_bvh import _SnapshotBVH
from bench.physics_static_bench import (
    _indexed,
    _indexed_contacts,
    _indexed_ray,
    _less,
    _shapes,
    _snapshot,
    _sweep,
    _sweep_order,
    _world,
)
from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.physics.collide import WorldShape, collide
from extensions.physics.world import PhysicsWorld
from extensions.physics.shape import Shape
from math.bounds import Box3
from math.quaternion import Quaternion
from math.ray import Ray
from math.sort_utils import stable_sort
from math.vector3 import Vector3
from math.triangle import Triangle
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Angle, DEGREE, Duration, Length, Mass


def _box(x: Float32, y: Float32, z: Float32, r: Float32 = 0.5) -> Box3:
    return Box3(Vector3(x - r, y - r, z - r), Vector3(x + r, y + r, z + r))


def _oracle(tree: _SnapshotBVH, query: Box3) raises:
    var found = List[Int]()
    _ = tree.overlap(query, found)
    stable_sort[_less](found)
    var next = 0
    for i in range(len(tree.boxes)):
        if tree.boxes[i].intersects_box(query):
            assert_true(next < len(found))
            assert_equal(found[next], i)
            next += 1
    assert_equal(next, len(found))


def _ray_oracle(tree: _SnapshotBVH, ray: Ray) raises:
    var found = List[Int]()
    _ = tree.ray(ray, found)
    stable_sort[_less](found)
    var next = 0
    for i in range(len(tree.boxes)):
        if ray.intersects_box(tree.boxes[i]):
            assert_true(next < len(found))
            assert_equal(found[next], i)
            next += 1
    assert_equal(next, len(found))


def test_empty_singleton_rebuild_and_owned_bounds() raises:
    var tree = _SnapshotBVH()
    var found = List[Int](length=2, fill=1)
    assert_equal(tree.overlap(_box(0, 0, 0), found), 0)
    assert_equal(len(found), 0)
    assert_equal(tree.ray(Ray(Vector3(0, 0, 0), Vector3(1, 0, 0)), found), 0)
    var boxes = List[Box3](length=1, fill=_box(0, 0, 0))
    tree.rebuild(boxes)
    assert_equal(len(tree.nodes), 1)
    boxes[0] = _box(100, 100, 100)
    _oracle(tree, _box(0, 0, 0))
    tree.rebuild(boxes)
    _oracle(tree, _box(0, 0, 0))
    tree.rebuild(List[Box3]())
    assert_equal(len(tree.nodes), 0)


def test_refit_preserves_mapping_and_rejects_partial_updates() raises:
    var tree = _SnapshotBVH()
    tree.refit(List[Box3]())
    var boxes = List[Box3]()
    for i in range(37):
        boxes.append(_box(Float32(i), 0, 0))
    tree.rebuild(boxes)
    for i in range(37):
        boxes[i] = _box(0, Float32(36 - i), 0)
    tree.refit(boxes)
    assert_equal(len(tree.nodes), 73)
    for box in boxes:
        _oracle(tree, box)
    _ray_oracle(tree, Ray(Vector3(0, -10, 0), Vector3(0, 1, 0)))
    var failed = False
    try:
        tree.refit(List[Box3]())
    except:
        failed = True
    assert_true(failed)
    boxes[3] = Box3.empty()
    failed = False
    try:
        tree.refit(boxes)
    except:
        failed = True
    assert_true(failed)
    _oracle(tree, _box(0, 33, 0))


def test_sorted_reverse_coincident_and_three_axis_splits() raises:
    for axis in range(3):
        for reverse in [False, True]:
            var boxes = List[Box3]()
            for i in range(67):
                var p = Float32(66 - i if reverse else i) * 2
                boxes.append(
                    _box(
                        p if axis == 0 else 0,
                        p if axis == 1 else 0,
                        p if axis == 2 else 0,
                    )
                )
            var tree = _SnapshotBVH()
            tree.rebuild(boxes)
            assert_equal(len(tree.nodes), 2 * len(boxes) - 1)
            for box in boxes:
                _oracle(tree, box)
            _oracle(tree, _box(-100, -100, -100))
            _oracle(tree, _box(0, 0, 0, 1000))
    var coincident = List[Box3](length=33, fill=_box(1, 1, 1))
    var tree = _SnapshotBVH()
    tree.rebuild(coincident)
    _oracle(tree, _box(1, 1, 1))
    assert_equal(len(tree.nodes), 65)
    assert_equal(tree.nodes[0].escape, 65)


def test_closed_boundaries_empty_queries_and_negative_rays() raises:
    var boxes = List[Box3]()
    for i in range(17):
        boxes.append(
            _box(Float32(i) - 8, Float32(i % 3) - 1, Float32(i % 5) - 2)
        )
    boxes.append(Box3(Vector3(0, 0, 0), Vector3(0, 0, 0)))
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    for i in range(20):
        _oracle(tree, _box(Float32(i) - 10, 0, 0))
        _oracle(tree, _box(Float32(i) - 10, 1, 0, 0))
    _oracle(tree, Box3.empty())
    for direction in [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, -1),
        Vector3(1, 2, 3),
    ]:
        for origin in [
            Vector3(0, 0, 0),
            Vector3(-100, 0, 0),
            Vector3(0, 100, 0),
            Vector3(0.5, 0.5, 0.5),
        ]:
            _ray_oracle(tree, Ray(origin, direction))


def test_refuse_invalid_rebuild_without_losing_snapshot() raises:
    var tree = _SnapshotBVH()
    tree.rebuild(List[Box3](length=1, fill=_box(0, 0, 0)))
    var invalid = List[Box3](length=1, fill=Box3.empty())
    for value in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for component in range(6):
            var box = _box(0, 0, 0)
            if component == 0:
                box.min.x = value
            if component == 1:
                box.min.y = value
            if component == 2:
                box.min.z = value
            if component == 3:
                box.max.x = value
            if component == 4:
                box.max.y = value
            if component == 5:
                box.max.z = value
            invalid.append(box)
    for box in invalid:
        var rejected = False
        try:
            tree.rebuild(List[Box3](length=1, fill=box))
        except:
            rejected = True
        assert_true(rejected)
        assert_equal(len(tree.boxes), 1)
        _oracle(tree, _box(0, 0, 0))


def _check_world(mut world: PhysicsWorld) raises:
    if world._dirty:
        world._rebuild()
    var expected_manifolds = world._find_contacts()
    var actual_manifolds = _indexed_contacts(world)
    assert_equal(len(actual_manifolds), len(expected_manifolds))
    for i in range(len(actual_manifolds)):
        assert_equal(actual_manifolds[i].a, expected_manifolds[i].a)
        assert_equal(actual_manifolds[i].b, expected_manifolds[i].b)
        assert_equal(
            len(actual_manifolds[i].points), len(expected_manifolds[i].points)
        )
        for p in range(len(actual_manifolds[i].points)):
            var expected = expected_manifolds[i].points[p].contact
            var actual = actual_manifolds[i].points[p].contact
            assert_equal(actual.depth, expected.depth)
            assert_true(actual.point == expected.point)
            assert_true(actual.normal == expected.normal)
    var snapshot = _snapshot(world)
    var boxes = snapshot[0].copy()
    var owners = snapshot[1].copy()
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    var order = List[Int]()
    for i in range(len(boxes)):
        order.append(i)
    _sweep_order(boxes, order)
    var old = _sweep(world, boxes, owners, order)
    var new = _indexed(world, boxes, owners, tree, order)
    assert_equal(old[1], new[1])
    assert_equal(old[2], new[2])
    # Pure transforms repeat for each brute-force pair. Keep a fresh owned
    # copy per active body for this check; rebuild it after every mutation.
    var oracle_shapes = List[WorldShape](capacity=len(owners))
    for owner in owners:
        oracle_shapes.append(world._shape(owner))
    # Exact per-query membership, no checksum collisions or duplicate ids.
    var found = List[Int]()
    var contacts = 0
    for a in range(len(boxes)):
        if not world.bodies[owners[a]].is_dynamic():
            continue
        var query = boxes[a]
        query.expand_by_scalar(world.margin)
        _ = tree.overlap(query, found)
        stable_sort[_less](found)
        var position = 0
        for b in range(len(boxes)):
            var in_bounds = query.intersects_box(boxes[b])
            if in_bounds:
                assert_true(position < len(found))
                assert_equal(found[position], b)
                position += 1
            if b == a:
                continue
            # Brute force runs narrow phase on every body, including bodies
            # that the bounds query rejects. A contact must never be culled.
            var points = collide(
                oracle_shapes[a], oracle_shapes[b], world.margin
            )
            if len(points) > 0:
                assert_true(in_bounds)
                contacts += len(points)
        assert_equal(position, len(found))
    for origin in [
        Vector3(-10, 0, 0),
        Vector3(0, 10, 0),
        Vector3(2, 0, 0),
        Vector3(0, 0, -10),
        Vector3(100, 100, 100),
    ]:
        for direction in [
            Vector3(1, 0, 0),
            Vector3(0, -1, 0),
            Vector3(0, 0, 1),
        ]:
            for ignore in [BodyId(-1), BodyId(0)]:
                var ray = Ray(origin, direction)
                var expected = world.raycast(
                    origin, direction, Length(1000), ignore
                )
                var actual = _indexed_ray(
                    world, tree, owners, ray, 1000, ignore, found
                )
                assert_equal(Bool(expected), Bool(actual))
                if Bool(expected):
                    assert_equal(
                        expected.value().body.value, actual.value().body.value
                    )
                    assert_equal(
                        expected.value().distance, actual.value().distance
                    )
                    assert_true(expected.value().point == actual.value().point)
                    assert_true(
                        expected.value().normal == actual.value().normal
                    )


def test_all_shapes_modes_insertion_removal_transform_and_margin() raises:
    var shapes = _shapes()
    var world = PhysicsWorld()
    for i in range(12):
        var body = RigidBody(
            DYNAMIC,
            shapes[i % 4].copy(),
            Mass(1),
            Vector3(Float32(i % 3), 0, 0),
            Quaternion.identity(),
        )
        if i % 3 == 0:
            body.set_kind(STATIC)
        if i % 3 == 1:
            body.set_kind(KINEMATIC)
        _ = world.add_body(body^)
    _check_world(world)
    for step in range(6):
        world.bodies[step].collides = False
        world.bodies[11 - step].position = Vector3(10, 20, 30)
        world.bodies[6].set_kind(STATIC if step % 2 == 0 else DYNAMIC)
        world.bodies[7].shape_position = Vector3(0, 0, Float32(step))
        world.bodies[8].rotation = Quaternion.from_axis_angle(
            Vector3(0, 0, 1), Angle(Float32(step) * 17, DEGREE)
        )
        world.bodies[9].shape_rotation = Quaternion.from_axis_angle(
            Vector3(0, 1, 0), Angle(Float32(step) * 13, DEGREE)
        )
        _check_world(world)
    for i in range(12):
        world.bodies[i].collides = True
        world.bodies[i].position = Vector3(
            Float32(i) * (1 + world.margin), 0, 0
        )
    _check_world(world)


def test_grid_distribution_contact_and_ray_oracles() raises:
    var sample = _world(37, 9, 0)
    _check_world(sample)


def test_overlapping_x_distribution_contact_and_ray_oracles() raises:
    var sample = _world(37, 9, 1)
    _check_world(sample)


def test_clustered_distribution_contact_and_ray_oracles() raises:
    var sample = _world(37, 9, 2)
    _check_world(sample)


def test_coincident_distribution_contact_and_ray_oracles() raises:
    var sample = _world(37, 9, 3)
    _check_world(sample)


def test_mixed_mesh_dirty_clean_ties_ignore_and_disabled_owners() raises:
    var world = PhysicsWorld()
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(
                [
                    Triangle(
                        Vector3(-2, -2, 0), Vector3(2, -2, 0), Vector3(0, 2, 0)
                    )
                ]
            ),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    _ = world.add_body(
        RigidBody(
            DYNAMIC,
            Shape.box(Length(0.5), Length(0.5), Length(0.5)),
            Mass(1),
            Vector3(0, 0, -0.5),
            Quaternion.identity(),
        )
    )
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.sphere(Length(0.5)),
            Mass(0),
            Vector3(0, 0, -0.5),
            Quaternion.identity(),
        )
    )
    for clean in [False, True]:
        if clean:
            world._rebuild()
        var snapshot = _snapshot(world)
        var tree = _SnapshotBVH()
        tree.rebuild(snapshot[0])
        var found = List[Int]()
        for ignore in [BodyId(-1), BodyId(0), BodyId(1), BodyId(2)]:
            for reach in [
                Float32(-1),
                Float32(0),
                Float32(1.999),
                Float32(2),
                Float32(3),
            ]:
                var ray = Ray(Vector3(0, 0, 2), Vector3(0, 0, -1))
                var expected = world.raycast(
                    ray.origin, ray.direction, Length(reach), ignore
                )
                var actual = _indexed_ray(
                    world, tree, snapshot[1], ray, reach, ignore, found
                )
                assert_equal(Bool(expected), Bool(actual))
                if Bool(expected):
                    assert_equal(
                        expected.value().body.value, actual.value().body.value
                    )
                    assert_equal(
                        expected.value().distance, actual.value().distance
                    )
    _check_world(world)
    world.bodies[0].collides = False
    _check_world(world)


def test_history_ties_and_adjacent_margin_boundaries() raises:
    var world = _world(4, 4, 0)
    world.bodies[0].position.x = 100
    _check_world(world)
    for i in range(len(world.bodies)):
        world.bodies[i].position = Vector3(0, 0, 0)
    # Preserve the preexisting sweep order when all x minima become equal.
    _check_world(world)
    for margin in [Float32(0), Float32(0.02), Float32(0.1), Float32(-0.01)]:
        world.margin = margin
        for i in range(len(world.bodies)):
            world.bodies[i].position = Vector3(Float32(i) * (1 + margin), 0, 0)
        _check_world(world)


def _step_candidate(mut world: PhysicsWorld) raises:
    var h = Float32(0.01)
    world._integrate_velocities(h)
    if world._dirty:
        world._rebuild()
    var manifolds = _indexed_contacts(world)
    world._prepare(manifolds, h)
    for _ in range(world.velocity_iterations):
        for m in range(len(manifolds)):
            world._solve_velocity(manifolds[m], h)
    for m in range(len(manifolds)):
        world._restitution(manifolds[m])
    for _ in range(world.position_iterations):
        for m in range(len(manifolds)):
            world._solve_push(manifolds[m], h)
    world._integrate_positions(h)
    world._report(manifolds)


def test_ordered_manifolds_produce_identical_impulses_and_trajectories() raises:
    var baseline = _world(17, 7, 2)
    var candidate = _world(17, 7, 2)
    for i in range(17, 24):
        baseline.bodies[i].linear_velocity = Vector3(-1, 0, -0.2)
        candidate.bodies[i].linear_velocity = Vector3(-1, 0, -0.2)
    for tick in range(12):
        if tick == 3:
            baseline.bodies[0].collides = False
            candidate.bodies[0].collides = False
        if tick == 5:
            baseline.bodies[0].collides = True
            candidate.bodies[0].collides = True
            baseline.bodies[17].set_kind(KINEMATIC)
            candidate.bodies[17].set_kind(KINEMATIC)
        if tick == 7:
            baseline.bodies[17].set_kind(DYNAMIC)
            candidate.bodies[17].set_kind(DYNAMIC)
        baseline.step(Duration(0.01))
        _step_candidate(candidate)
        assert_equal(baseline.contact_count, candidate.contact_count)
        assert_equal(len(baseline.events), len(candidate.events))
        for i in range(len(baseline.events)):
            assert_equal(
                baseline.events[i].body.value, candidate.events[i].body.value
            )
            assert_equal(
                baseline.events[i].other.value, candidate.events[i].other.value
            )
            assert_true(
                baseline.events[i].normal_impulse
                == candidate.events[i].normal_impulse
            )
        for i in range(len(baseline.bodies)):
            assert_true(
                baseline.bodies[i].position == candidate.bodies[i].position
            )
            assert_true(
                baseline.bodies[i].linear_velocity
                == candidate.bodies[i].linear_velocity
            )
            assert_true(
                baseline.bodies[i].angular_velocity
                == candidate.bodies[i].angular_velocity
            )
            assert_equal(
                baseline.bodies[i].rotation.x, candidate.bodies[i].rotation.x
            )
            assert_equal(
                baseline.bodies[i].rotation.y, candidate.bodies[i].rotation.y
            )
            assert_equal(
                baseline.bodies[i].rotation.z, candidate.bodies[i].rotation.z
            )
            assert_equal(
                baseline.bodies[i].rotation.w, candidate.bodies[i].rotation.w
            )


def test_extreme_finite_and_tiny_bounds() raises:
    var boxes = List[Box3]()
    boxes.append(Box3(Vector3(2e38, 2e38, 2e38), Vector3(3e38, 3e38, 3e38)))
    boxes.append(
        Box3(Vector3(-3e38, -3e38, -3e38), Vector3(-2e38, -2e38, -2e38))
    )
    boxes.append(
        Box3(Vector3(-1e-38, -1e-38, -1e-38), Vector3(1e-38, 1e-38, 1e-38))
    )
    boxes.append(Box3(Vector3(0, 0, 0), Vector3(0, 0, 0)))
    var tree = _SnapshotBVH()
    tree.rebuild(boxes)
    for box in boxes:
        _oracle(tree, box)
    for direction in [Vector3(1, 1, 1), Vector3(-1, -1, -1), Vector3(1, 0, 0)]:
        _ray_oracle(tree, Ray(Vector3(0, 0, 0), direction))
    tree.refit(boxes)
    for box in boxes:
        _oracle(tree, box)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
