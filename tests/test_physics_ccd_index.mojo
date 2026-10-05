# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Adversarial controls for conservative sphere/mesh CCD candidates (#636)."""

from extensions.physics.body import BodyId, DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import DISCRETE, SPHERE_MESH_CCD, _sweep_domain
from extensions.physics.ccd_index import _CCDIndex, _bounds, _down, _up
from extensions.physics.shape import Shape, PhysicsMaterial, _wide
from extensions.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, Length, Mass


def _floor(z: Float32 = 0, ceiling: Bool = False) -> Triangle:
    var a = Vector3(-100, -100, z)
    var b = Vector3(100, -100, z)
    var c = Vector3(0, 100, z)
    if ceiling:
        return Triangle(a, c, b)
    return Triangle(a, b, c)


def _mesh(var triangles: List[Triangle]) raises -> RigidBody:
    var body = RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0, 0)
    return body^


def _padding(i: Int) -> Triangle:
    # Alternate sides so insertion order differs from spatial order.
    var x = Float32(200 + 20 * i)
    if i % 2 == 0:
        x = -x
    return Triangle(
        Vector3(x, 200, 0),
        Vector3(x + 10, 200, 0),
        Vector3(x, 210, 0),
    )


def _world(
    triangle: Triangle,
    position: Vector3,
    velocity: Vector3,
    brute: Bool = False,
    radius: Float32 = 0.1,
    bounce: Float32 = 0,
    count: Int = 17,
) raises -> PhysicsWorld:
    var triangles = List[Triangle]()
    for i in range(count):
        if i == count // 2:
            triangles.append(triangle)
        else:
            triangles.append(_padding(i))
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    _ = world.add_body(_mesh(triangles^))
    var sphere = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(radius)),
        Mass(1),
        position,
        Quaternion.identity(),
    )
    sphere.linear_velocity = velocity
    sphere.material = PhysicsMaterial(0, bounce)
    _ = world.add_body(sphere^)
    return world^


def _assert_body(a: RigidBody, b: RigidBody) raises:
    assert_true(a.position == b.position)
    assert_true(a.rotation == b.rotation)
    assert_true(a.linear_velocity == b.linear_velocity)
    assert_true(a.angular_velocity == b.angular_velocity)
    assert_true(a.force == b.force)
    assert_true(a.torque == b.torque)
    assert_true(a.push_velocity == b.push_velocity)
    assert_true(a.push_angular == b.push_angular)


def _assert_world(a: PhysicsWorld, b: PhysicsWorld) raises:
    # The independent all-triangle path must retain arithmetic, event order,
    # force consumption, split state, and octree lifecycle exactly.
    assert_equal(len(a.bodies), len(b.bodies))
    for i in range(len(a.bodies)):
        _assert_body(a.bodies[i], b.bodies[i])
    assert_equal(a.contact_count, b.contact_count)
    assert_equal(len(a.events), len(b.events))
    for i in range(len(a.events)):
        assert_equal(a.events[i].body, b.events[i].body)
        assert_equal(a.events[i].other, b.events[i].other)
        assert_true(a.events[i].normal_impulse == b.events[i].normal_impulse)
    assert_equal(a._order, b._order)
    assert_equal(a._dirty, b._dirty)


def _step_pair(
    mut indexed: PhysicsWorld, mut brute: PhysicsWorld, dt: Float32
) raises:
    indexed.step(Duration(dt))
    brute.step(Duration(dt))
    _assert_world(indexed, brute)
    assert_true(brute._ccd_brute_force)
    assert_equal(brute._ccd_index.count, -1)
    assert_equal(len(brute._ccd_index.nodes), 0)


def _failure_pair(
    mut indexed: PhysicsWorld, mut brute: PhysicsWorld, dt: Float32
) raises:
    var before = indexed.bodies.copy()
    var events = indexed.events.copy()
    var count = indexed.contact_count
    var order = indexed._order.copy()
    var dirty = indexed._dirty
    with assert_raises():
        indexed.step(Duration(dt))
    with assert_raises():
        brute.step(Duration(dt))
    _assert_world(indexed, brute)
    for i in range(len(before)):
        _assert_body(indexed.bodies[i], before[i])
    assert_equal(indexed.contact_count, count)
    assert_equal(indexed._order, order)
    assert_equal(indexed._dirty, dirty)
    assert_equal(len(indexed.events), len(events))
    for i in range(len(events)):
        assert_equal(indexed.events[i].body, events[i].body)
        assert_equal(indexed.events[i].other, events[i].other)
        assert_true(
            indexed.events[i].normal_impulse == events[i].normal_impulse
        )


def _reset(mut world: PhysicsWorld, position: Vector3, velocity: Vector3):
    world.bodies[1].position = position
    world.bodies[1].rotation = Quaternion.identity()
    world.bodies[1].linear_velocity = velocity
    world.bodies[1].angular_velocity = Vector3(0, 0, 0)


def test_face_edges_vertices_and_grazing_match_full_scan() raises:
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
    )
    var starts = [
        Vector3(2, 2, 2),
        Vector3(2, -0.6, 2),
        Vector3(-0.6, 2, 2),
        Vector3(5.4, 5.4, 2),
        Vector3(-0.6, -0.6, 2),
        Vector3(10.6, -0.6, 2),
        Vector3(-0.6, 10.6, 2),
        Vector3(2, -0.999, 2),
        Vector3(2, -1, 2),
        Vector3(2, -1.001, 2),
    ]
    for i in range(len(starts)):
        var indexed = _world(triangle, starts[i], Vector3(0, 0, -40), radius=1)
        var brute = _world(triangle, starts[i], Vector3(0, 0, -40), True, 1)
        _step_pair(indexed, brute, 0.1)
        if i < 8:
            assert_true(indexed.contact_count >= 1)
        else:
            assert_equal(indexed.contact_count, 0)
        assert_true(len(indexed._ccd_index.nodes) > 0)
    var lateral = _world(
        triangle, Vector3(2, -2, 0.6), Vector3(0, 40, 0), radius=1
    )
    var reference = _world(
        triangle, Vector3(2, -2, 0.6), Vector3(0, 40, 0), True, 1
    )
    _step_pair(lateral, reference, 0.1)
    assert_true(lateral.contact_count >= 1)


def test_slow_overlap_backface_and_repeat_parity() raises:
    for start in [Float32(0.09), Float32(0.1), Float32(0.115), Float32(-0.05)]:
        for speed in [Float32(-30), Float32(-0.1), Float32(0), Float32(0.1)]:
            var indexed = _world(
                _floor(), Vector3(0, 0, start), Vector3(0, 0, speed)
            )
            var brute = _world(
                _floor(), Vector3(0, 0, start), Vector3(0, 0, speed), True
            )
            for _ in range(3):
                _step_pair(indexed, brute, 0.01)
            if start < 0:
                assert_equal(indexed.contact_count, 0)


def test_equal_triangle_and_sphere_times_retain_insertion_order() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30))
    var brute = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30), True)
    # The later owner has a lower x centroid and is visited first by the
    # index. Equal hit times must still choose the earlier triangle owner.
    var second_mesh = _mesh(
        [
            Triangle(
                Vector3(-200, -100, 0),
                Vector3(100, -100, 0),
                Vector3(0, 100, 0),
            )
        ]
    )
    second_mesh.material = PhysicsMaterial(0, 1)
    _ = indexed.add_body(second_mesh.copy())
    _ = brute.add_body(second_mesh^)
    var sphere = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(10, 0, 0.15),
        Quaternion.identity(),
    )
    sphere.linear_velocity = Vector3(0, 0, -30)
    sphere.material = PhysicsMaterial(0, 0)
    _ = indexed.add_body(sphere.copy())
    _ = brute.add_body(sphere^)
    indexed._validate_ccd()
    var candidates = List[Int]()
    _ = indexed._ccd_index.query(
        _wide(Vector3(0, 0, 0.15)),
        _wide(Vector3(0, 0, -0.3)),
        Float64(indexed.bodies[1].shape.radius),
        candidates,
    )
    assert_equal(len(candidates), 2)
    assert_equal(candidates[0], 17)
    assert_equal(candidates[1], 8)
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed.contact_count, 2)
    assert_equal(len(indexed.events), 4)
    assert_equal(indexed.events[0].body.value, 1)
    assert_equal(indexed.events[0].other.value, 0)
    assert_equal(indexed.events[2].body.value, 3)
    assert_equal(indexed.events[2].other.value, 0)
    assert_equal(indexed.bodies[1].linear_velocity.z, 0)
    assert_equal(indexed.bodies[3].linear_velocity.z, 0)


def test_multiple_rebounds_and_transaction_rollback() raises:
    var indexed = _world(
        _floor(), Vector3(0, 0, 0.5), Vector3(0, 0, -300), bounce=1
    )
    var brute = _world(
        _floor(), Vector3(0, 0, 0.5), Vector3(0, 0, -300), True, 0.1, 1
    )
    _ = indexed.add_body(_mesh([_floor(1, True)]))
    _ = brute.add_body(_mesh([_floor(1, True)]))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed.contact_count, 4)
    assert_equal(len(indexed.events), 8)
    assert_almost_equal(indexed.bodies[1].position.z, 0.7, atol=1e-6)
    _reset(indexed, Vector3(0, 0, 0.5), Vector3(0, 0, -300))
    _reset(brute, Vector3(0, 0, 0.5), Vector3(0, 0, -300))
    indexed.ccd_max_impacts = 1
    brute.ccd_max_impacts = 1
    indexed.bodies[1].force = Vector3(1, 2, 3)
    brute.bodies[1].force = Vector3(1, 2, 3)
    indexed.bodies[1].torque = Vector3(0, 1, 0)
    brute.bodies[1].torque = Vector3(0, 1, 0)
    indexed.bodies[1].push_velocity = Vector3(0.1, 0, 0.2)
    brute.bodies[1].push_velocity = Vector3(0.1, 0, 0.2)
    indexed.bodies[1].push_angular = Vector3(0, 0.1, 0)
    brute.bodies[1].push_angular = Vector3(0, 0.1, 0)
    # Invalidate both mesh indexes. Failure must preserve prior reports and
    # dirty state even when an acceleration structure was rebuilt in flight.
    _ = indexed.add_body(_mesh([_floor()]))
    _ = brute.add_body(_mesh([_floor()]))
    assert_true(indexed._dirty)
    _failure_pair(indexed, brute, 0.01)
    var a = indexed.raycast(
        Vector3(10, 0, 0.5), Vector3(0, 0, -1), Length(1), BodyId(-1)
    ).value()
    var b = brute.raycast(
        Vector3(10, 0, 0.5), Vector3(0, 0, -1), Length(1), BodyId(-1)
    ).value()
    assert_equal(a.body.value, 0)
    assert_equal(a.body, b.body)
    assert_equal(a.distance, b.distance)
    indexed.ccd_max_impacts = 16
    brute.ccd_max_impacts = 16
    _step_pair(indexed, brute, 0.01)


def test_warm_cache_observes_ghosts_materials_and_forces() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0))
    var brute = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0), True)
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 17)
    for enabled in [False, True]:
        indexed.bodies[0].collides = enabled
        brute.bodies[0].collides = enabled
        _reset(indexed, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        _reset(brute, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        _step_pair(indexed, brute, 0.01)
        assert_equal(indexed.contact_count, Int(enabled))
    indexed.bodies[0].material = PhysicsMaterial(1, 0.5)
    brute.bodies[0].material = PhysicsMaterial(1, 0.5)
    indexed.bodies[1].material = PhysicsMaterial(1, 0)
    brute.bodies[1].material = PhysicsMaterial(1, 0)
    _reset(indexed, Vector3(0, 0, 0.4), Vector3(7, 0, -30))
    _reset(brute, Vector3(0, 0, 0.4), Vector3(7, 0, -30))
    indexed.bodies[1].angular_velocity = Vector3(0, 10, 0)
    brute.bodies[1].angular_velocity = Vector3(0, 10, 0)
    _step_pair(indexed, brute, 0.02)
    assert_equal(indexed.bodies[1].linear_velocity.z, 15)
    assert_true(indexed.bodies[1].linear_velocity.x < 7)
    assert_true(indexed.bodies[1].rotation != Quaternion.identity())
    for enabled in [False, True]:
        indexed.bodies[1].collides = enabled
        brute.bodies[1].collides = enabled
        _reset(indexed, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        _reset(brute, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        indexed.bodies[1].force = Vector3(1, 2, 3)
        brute.bodies[1].force = Vector3(1, 2, 3)
        _step_pair(indexed, brute, 0.01)
        assert_equal(indexed.contact_count, Int(enabled))
        assert_true(indexed.bodies[1].force == Vector3(0, 0, 0))
    assert_equal(indexed._ccd_index.count, 17)


def test_add_mesh_invalidates_and_public_edits_keep_snapshot() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0))
    var brute = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0), True)
    assert_equal(indexed._ccd_index.count, -1)
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 17)
    _ = indexed.add_body(_mesh([_floor(1)]))
    _ = brute.add_body(_mesh([_floor(1)]))
    assert_equal(indexed._ccd_index.count, -1)
    _reset(indexed, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 18)
    assert_equal(indexed.events[0].other.value, 2)
    assert_almost_equal(indexed.bodies[1].position.z, 1.1, atol=1e-7)
    indexed.bodies[2].position = Vector3(100, 100, 100)
    brute.bodies[2].position = Vector3(100, 100, 100)
    indexed.bodies[2].rotation = Quaternion(0, 0, 1, 0)
    brute.bodies[2].rotation = Quaternion(0, 0, 1, 0)
    indexed.bodies[2].shape_position = Vector3(5, 0, 0)
    brute.bodies[2].shape_position = Vector3(5, 0, 0)
    indexed.bodies[2].shape = Shape.mesh([_floor(20)])
    brute.bodies[2].shape = Shape.mesh([_floor(20)])
    _reset(indexed, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 18)
    assert_equal(indexed.events[0].other.value, 2)
    assert_almost_equal(indexed.bodies[1].position.z, 1.1, atol=1e-7)


def test_cold_and_invalidated_caches_refuse_off_query_bad_geometry() raises:
    for choice in range(6):
        var bad = Triangle(
            Vector3(500, 500, 500),
            Vector3(500, 500, 500),
            Vector3(500, 500, 500),
        )
        if choice == 1:
            # The wide normal is nonzero, but the Float32 raw normal is zero.
            bad = Triangle(
                Vector3(0, 0, 500),
                Vector3(1e-30, 0, 500),
                Vector3(0, 1e-30, 500),
            )
        elif choice == 2:
            bad = Triangle(
                Vector3(0, 0, 500),
                Vector3(10, 0, 500),
                Vector3(0, 1e-7, 500),
            )
        elif choice == 3:
            bad.a.x = nan[DType.float32]()
        elif choice == 4:
            bad.a.x = inf[DType.float32]()
        elif choice == 5:
            bad.a.x = 1000001
        for warm in [False, True]:
            var indexed = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0))
            var brute = _world(
                _floor(), Vector3(0, 0, 2), Vector3(0, 0, 0), True
            )
            if warm:
                _step_pair(indexed, brute, 0.01)
                assert_equal(indexed._ccd_index.count, 17)
            var owner = _mesh([bad])
            owner.collides = False
            _ = indexed.add_body(owner.copy())
            _ = brute.add_body(owner^)
            assert_equal(indexed._ccd_index.count, -1)
            indexed.bodies[1].force = Vector3(1, 2, 3)
            brute.bodies[1].force = Vector3(1, 2, 3)
            _failure_pair(indexed, brute, 0.01)
            # A rejected snapshot must not become a valid cached snapshot.
            assert_equal(indexed._ccd_index.count, -1)


def test_warm_geometry_cache_still_validates_live_body_state() raises:
    for choice in range(4):
        var indexed = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0))
        var brute = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0), True)
        _step_pair(indexed, brute, 0.01)
        if choice == 0:
            indexed.bodies[0].collides = False
            brute.bodies[0].collides = False
            indexed.bodies[0].material = PhysicsMaterial(-1, 0)
            brute.bodies[0].material = PhysicsMaterial(-1, 0)
        elif choice == 1:
            indexed.bodies[0].linear_velocity = Vector3(1, 0, 0)
            brute.bodies[0].linear_velocity = Vector3(1, 0, 0)
        elif choice == 2:
            indexed.bodies[1].shape = Shape.capsule(Length(0.1), Length(0.2))
            brute.bodies[1].shape = Shape.capsule(Length(0.1), Length(0.2))
        else:
            indexed.ccd_max_impacts = 0
            brute.ccd_max_impacts = 0
        _failure_pair(indexed, brute, 0.01)


def test_precision_boundaries_and_nearby_oversized_refusal() raises:
    # A sphere at its coordinate/radius limit hits exactly at the endpoint.
    for sign in [Float32(-1), Float32(1)]:
        var x = sign * 8192
        var triangle = Triangle(
            Vector3(x - 10, -10, 0),
            Vector3(x + 10, -10, 0),
            Vector3(x, 10, 0),
        )
        var indexed = _world(
            triangle, Vector3(x, 0, 0.625), Vector3(0, 0, -1), radius=0.125
        )
        var brute = _world(
            triangle, Vector3(x, 0, 0.625), Vector3(0, 0, -1), True, 0.125
        )
        _step_pair(indexed, brute, 0.5)
        assert_equal(indexed.contact_count, 1)
        assert_equal(indexed.bodies[1].position.z, 0.125)
    # Exactly 1048576 radii is supported. One meter beyond is refused.
    for extent in [Float32(131072), Float32(131073)]:
        var triangle = Triangle(
            Vector3(-extent, -extent, 0),
            Vector3(extent, -extent, 0),
            Vector3(0, extent, 0),
        )
        var indexed = _world(
            triangle, Vector3(0, 0, 0.625), Vector3(0, 0, -1), radius=0.125
        )
        var brute = _world(
            triangle, Vector3(0, 0, 0.625), Vector3(0, 0, -1), True, 0.125
        )
        if extent == 131072:
            _step_pair(indexed, brute, 0.5)
            assert_equal(indexed.bodies[1].position.z, 0.125)
        else:
            _failure_pair(indexed, brute, 0.5)
    # Reach validation is wider than the downward sweep. A huge triangle
    # behind the sphere at the reachable-ball boundary must still refuse.
    # One Float32 increment beyond that boundary is safely out of range.
    for z in [Float32(1.25), Float32(1.2500001192092896)]:
        var triangle = Triangle(
            Vector3(-131073, -131073, z),
            Vector3(131073, -131073, z),
            Vector3(0, 131073, z),
        )
        var indexed = _world(
            triangle, Vector3(0, 0, 0.625), Vector3(0, 0, -1), radius=0.125
        )
        var brute = _world(
            triangle, Vector3(0, 0, 0.625), Vector3(0, 0, -1), True, 0.125
        )
        indexed.margin = 0
        brute.margin = 0
        if z == 1.25:
            _failure_pair(indexed, brute, 0.5)
        else:
            _step_pair(indexed, brute, 0.5)
            assert_equal(indexed.contact_count, 0)
            assert_equal(indexed.bodies[1].position.z, 0.125)
    var limit = Triangle(
        Vector3(999800, -100, 0),
        Vector3(1000000, -100, 0),
        Vector3(999900, 100, 0),
    )
    var indexed = _world(
        limit, Vector3(999900, 0, 33), Vector3(0, 0, -300), radius=32
    )
    var brute = _world(
        limit, Vector3(999900, 0, 33), Vector3(0, 0, -300), True, 32
    )
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed.bodies[1].position.z, 32)


def test_empty_small_mesh_threshold_and_nonmesh_addition() raises:
    var empty = PhysicsWorld()
    assert_false(empty._ccd_brute_force)
    empty.collision_detection = SPHERE_MESH_CCD
    empty.step(Duration(0.01))
    assert_equal(empty._ccd_index.count, 0)
    assert_equal(len(empty._ccd_index.nodes), 0)
    for count in [1, 8, 9, 17]:
        var indexed = _world(
            _floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30), count=count
        )
        var brute = _world(
            _floor(),
            Vector3(0, 0, 0.15),
            Vector3(0, 0, -30),
            True,
            count=count,
        )
        _step_pair(indexed, brute, 0.01)
        assert_equal(indexed.contact_count, 1)
        assert_equal(indexed._ccd_index.count, count)
        if count <= 8:
            assert_equal(len(indexed._ccd_index.nodes), 0)
        else:
            assert_equal(len(indexed._ccd_index.nodes), 2 * count - 1)
        var ghost = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.1)),
            Mass(1),
            Vector3(100, 0, 2),
            Quaternion.identity(),
        )
        ghost.collides = False
        _ = indexed.add_body(ghost.copy())
        _ = brute.add_body(ghost^)
        assert_equal(indexed._ccd_index.count, count)
        _step_pair(indexed, brute, 0.01)
        if count == 8:
            _ = indexed.add_body(_mesh([_padding(20)]))
            _ = brute.add_body(_mesh([_padding(20)]))
            assert_equal(indexed._ccd_index.count, -1)
            _step_pair(indexed, brute, 0.01)
            assert_equal(indexed._ccd_index.count, 9)
            assert_equal(len(indexed._ccd_index.nodes), 17)


def test_minimum_and_maximum_radius_use_indexed_sweeps() raises:
    for radius in [Float32(0.0001), Float32(10000)]:
        # The minimum-radius case travels more than the unchanged margin,
        # so it reaches the sweep rather than a slow speculative contact.
        var velocity = Vector3(0, 0, -max(Float32(3), radius * 300))
        var position = Vector3(0, 0, radius * 1.5)
        var indexed = _world(_floor(), position, velocity, radius=radius)
        var brute = _world(_floor(), position, velocity, True, radius)
        _step_pair(indexed, brute, 0.01)
        assert_true(len(indexed._ccd_index.nodes) > 0)
        assert_equal(indexed.contact_count, 1)
        assert_equal(indexed.bodies[1].linear_velocity.z, 0)
        assert_almost_equal(
            indexed.bodies[1].position.z, radius, atol=Float64(radius) * 1e-6
        )


def test_discrete_to_ccd_and_mesh_added_while_discrete() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30))
    var brute = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30), True)
    indexed.collision_detection = DISCRETE
    brute.collision_detection = DISCRETE
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, -1)
    assert_almost_equal(indexed.bodies[1].position.z, -0.15, atol=1e-7)
    indexed.collision_detection = SPHERE_MESH_CCD
    brute.collision_detection = SPHERE_MESH_CCD
    _reset(indexed, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 17)
    assert_equal(indexed.contact_count, 1)
    indexed.collision_detection = DISCRETE
    brute.collision_detection = DISCRETE
    _ = indexed.add_body(_mesh([_floor(1)]))
    _ = brute.add_body(_mesh([_floor(1)]))
    _reset(indexed, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, -1)
    indexed.collision_detection = SPHERE_MESH_CCD
    brute.collision_detection = SPHERE_MESH_CCD
    _reset(indexed, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 1.25), Vector3(0, 0, -30))
    _step_pair(indexed, brute, 0.01)
    assert_equal(indexed._ccd_index.count, 18)
    assert_equal(indexed.events[0].other.value, 2)
    assert_almost_equal(indexed.bodies[1].position.z, 1.1, atol=1e-7)


def test_brute_override_and_return_preserve_warm_index() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0))
    var brute = _world(_floor(), Vector3(0, 0, 2), Vector3(0, 0, 0), True)
    _step_pair(indexed, brute, 0.01)
    var nodes = indexed._ccd_index.nodes.copy()
    assert_equal(indexed._ccd_index.count, 17)
    assert_true(len(nodes) > 0)
    for force_oracle in [True, False]:
        indexed._ccd_brute_force = force_oracle
        _reset(indexed, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        _reset(brute, Vector3(0, 0, 0.15), Vector3(0, 0, -30))
        indexed.step(Duration(0.01))
        brute.step(Duration(0.01))
        _assert_world(indexed, brute)
        assert_equal(indexed.contact_count, 1)
        assert_equal(indexed.events[0].other.value, 0)
        assert_equal(indexed._ccd_index.count, 17)
        assert_equal(len(indexed._ccd_index.nodes), len(nodes))
        for i in range(len(nodes)):
            assert_true(indexed._ccd_index.nodes[i].box.min == nodes[i].box.min)
            assert_true(indexed._ccd_index.nodes[i].box.max == nodes[i].box.max)
            assert_equal(indexed._ccd_index.nodes[i].entry, nodes[i].entry)
            assert_equal(indexed._ccd_index.nodes[i].escape, nodes[i].escape)

        if force_oracle:
            # Deliberate unsupported-state injection tests only the private
            # diagnostic oracle. Restore the exact snapshot before using
            # acceleration again; public mesh edits do not change it.
            var original = indexed._triangles[0]
            var invalid = Triangle(
                Vector3(500, 500, 500),
                Vector3(500, 500, 500),
                Vector3(500, 500, 500),
            )
            indexed._triangles[0] = invalid
            brute._triangles[0] = invalid
            _failure_pair(indexed, brute, 0.01)
            indexed._triangles[0] = original
            brute._triangles[0] = original
            assert_equal(indexed._ccd_index.count, 17)


def test_indexed_reachable_sphere_refusal_restores_pending_force() raises:
    var indexed = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30))
    var brute = _world(_floor(), Vector3(0, 0, 0.15), Vector3(0, 0, -30), True)
    _step_pair(indexed, brute, 0.01)
    assert_equal(len(indexed.events), 2)
    var stationary = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0.5, 0, 0.5),
        Quaternion.identity(),
    )
    _ = indexed.add_body(stationary.copy())
    _ = brute.add_body(stationary^)
    assert_equal(indexed._ccd_index.count, 17)
    _reset(indexed, Vector3(0, 0, 0.5), Vector3(0, 0, -30))
    _reset(brute, Vector3(0, 0, 0.5), Vector3(0, 0, -30))
    indexed.bodies[1].force = Vector3(1, 2, 3)
    brute.bodies[1].force = Vector3(1, 2, 3)
    indexed.bodies[1].torque = Vector3(0, 1, 0)
    brute.bodies[1].torque = Vector3(0, 1, 0)
    # The shapes start separated, but their conservative reachable regions
    # overlap. Refusal after velocity integration must not consume forces.
    _failure_pair(indexed, brute, 0.01)
    indexed.bodies[2].position.x = 5
    brute.bodies[2].position.x = 5
    _step_pair(indexed, brute, 0.01)
    assert_true(indexed.bodies[1].force == Vector3(0, 0, 0))
    assert_true(indexed.bodies[1].torque == Vector3(0, 0, 0))


def _contains(found: List[Int], entry: Int) -> Bool:
    for candidate in found:
        if candidate == entry:
            return True
    return False


def _assert_candidates(
    index: _CCDIndex,
    triangles: List[Triangle],
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    reach: Float64,
) raises:
    var found = List[Int]()
    var visited = index.query(start, travel, reach, found)
    assert_true(visited > 0)
    assert_true(visited <= len(index.nodes))
    for i in range(len(found)):
        assert_true(found[i] >= 0 and found[i] < len(triangles))
        for j in range(i):
            assert_true(found[i] != found[j])
    for i in range(len(triangles)):
        if _sweep_domain(start, travel, 1, reach, triangles[i]):
            assert_true(_contains(found, i))


def test_index_axis_splits_pruning_and_unique_candidates() raises:
    for axis in range(3):
        var triangles = List[Triangle]()
        for i in range(33):
            var offset = Vector3(0, 0, 0)
            var coordinate = Float32(20 * ((i * 17) % 33) - 320)
            if axis == 0:
                offset.x = coordinate
            elif axis == 1:
                offset.y = coordinate
            else:
                offset.z = coordinate
            triangles.append(
                Triangle(
                    offset,
                    offset + Vector3(1, 0, 0),
                    offset + Vector3(0, 1, 0),
                )
            )
        var index = _CCDIndex()
        assert_equal(index.count, -1)
        index.rebuild(triangles)
        assert_equal(index.count, 33)
        assert_equal(len(index.nodes), 65)
        assert_equal(index.nodes[0].escape, len(index.nodes))
        var leaves = List[Int]()
        for i in range(len(index.nodes)):
            assert_true(index.nodes[i].escape > i)
            assert_true(index.nodes[i].escape <= len(index.nodes))
            if index.nodes[i].entry >= 0:
                assert_false(_contains(leaves, index.nodes[i].entry))
                leaves.append(index.nodes[i].entry)
        assert_equal(len(leaves), 33)
        for direction in [Float32(-1), Float32(0), Float32(1)]:
            _assert_candidates(
                index,
                triangles,
                _wide(Vector3(0, 0, 0)),
                _wide(Vector3(2 * direction, 3 * direction, 4 * direction)),
                1,
            )
        var found = List[Int]()
        var visited = index.query(
            _wide(Vector3(0, 0, 0)), _wide(Vector3(0, 0, 0)), 1, found
        )
        assert_equal(len(found), 1)
        assert_true(visited < len(index.nodes))
        visited = index.query(
            _wide(Vector3(0, 0, 0)), _wide(Vector3(0, 0, 0)), 1000, found
        )
        assert_equal(len(found), 33)
        assert_equal(visited, len(index.nodes))
        visited = index.query(
            _wide(Vector3(1000000, 1000000, 1000000)),
            _wide(Vector3(0, 0, 0)),
            0,
            found,
        )
        assert_equal(len(found), 0)
        assert_equal(visited, 1)
        # A rebuild must replace old nodes, including the tiny/empty path.
        var small = List[Triangle]()
        small.append(triangles[0])
        index.rebuild(small)
        assert_equal(index.count, 1)
        assert_equal(len(index.nodes), 0)
        small.clear()
        index.rebuild(small)
        assert_equal(index.count, 0)
        found.append(999)
        visited = index.query(
            _wide(Vector3(0, 0, 0)), _wide(Vector3(0, 0, 0)), 1, found
        )
        assert_equal(visited, 0)
        assert_equal(len(found), 0)


def test_equal_centroids_and_query_boundary_containment() raises:
    var triangles = List[Triangle]()
    for _ in range(9):
        triangles.append(
            Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
        )
    var index = _CCDIndex()
    index.rebuild(triangles)
    for start in [
        Vector3(-1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(0, -1, 0),
        Vector3(0, 2, 0),
        Vector3(0, 0, -1),
        Vector3(0, 0, 1),
    ]:
        var found = List[Int]()
        var visited = index.query(
            _wide(start), _wide(Vector3(0, 0, 0)), 1, found
        )
        assert_equal(visited, len(index.nodes))
        assert_equal(len(found), 9)
        _assert_candidates(
            index, triangles, _wide(start), _wide(Vector3(0, 0, 0)), 1
        )
    # No Float32 narrowing of sub-ULP endpoint travel or query inflation.
    var tiny = SIMD[DType.float64, 4](1e-16, -1e-16, 0, 0)
    _assert_candidates(index, triangles, _wide(Vector3(-1, 2, 0)), tiny, 1)


def test_bounds_round_each_operation_outward() raises:
    for value in [
        Float64(-1000000),
        Float64(-1),
        Float64(0),
        Float64(1),
        Float64(1000000),
    ]:
        assert_true(_up(value) > value)
        assert_true(_down(value) < value)
        assert_equal(_down(value), -_up(-value))
    assert_true(_up(Float64(-0.0)) > 0)
    assert_true(_down(Float64(-0.0)) < 0)
    var start = SIMD[DType.float64, 4](1, -1, 0, 0)
    var travel = SIMD[DType.float64, 4](1e-16, -1e-16, 0, 0)
    var bounds = _bounds(start, travel, 0)
    assert_true(bounds[1][0] > 1)
    assert_true(bounds[0][1] < -1)
    assert_true(bounds[0][2] < 0)
    assert_true(bounds[1][2] > 0)
    for reach in [Float64(0), Float64(0.0001), Float64(10000)]:
        for sign in [Float64(-1), Float64(1)]:
            start = SIMD[DType.float64, 4](1000000, -1000000, 0.125, 0)
            travel = SIMD[DType.float64, 4](
                sign * 0.125, sign * 0.125, -0.25, 0
            )
            bounds = _bounds(start, travel, reach)
            for axis in range(3):
                var end = start[axis] + travel[axis]
                assert_true(bounds[0][axis] <= min(start[axis], end) - reach)
                assert_true(bounds[1][axis] >= max(start[axis], end) + reach)


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite^.run()
