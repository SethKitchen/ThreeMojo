# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Owned physics query captures, historical owners and exact ray oracles."""

from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.physics.query_snapshot import (
    PhysicsQuerySnapshot,
    SnapshotRaycastHit,
)
from extensions.physics.shape import MESH, PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld, RaycastHit
from math.quaternion import Quaternion
from math.ray import Ray
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, Angle, DEGREE, Length, Mass


def _shape(kind: Int) raises -> Shape:
    if kind == 0:
        return Shape.sphere(Length(0.5))
    if kind == 1:
        return Shape.box(Length(0.5), Length(0.75), Length(1))
    if kind == 2:
        return Shape.capsule(Length(0.5), Length(0.75))
    return Shape.convex(
        [
            Vector3(-0.5, -0.75, -1),
            Vector3(0.5, -0.75, -1),
            Vector3(0.5, 0.75, -1),
            Vector3(-0.5, 0.75, -1),
            Vector3(-0.5, -0.75, 1),
            Vector3(0.5, -0.75, 1),
            Vector3(0.5, 0.75, 1),
            Vector3(-0.5, 0.75, 1),
        ]
    )


def _body(kind: Int, at: Vector3 = Vector3(0, 0, 0)) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC, _shape(kind), Mass(1), at, Quaternion.identity()
    )
    body.material = PhysicsMaterial(0.25, 0.125)
    return body^


def _floor(z: Float32 = 0) -> Triangle:
    return Triangle(
        Vector3(-10, -10, z), Vector3(10, -10, z), Vector3(0, 10, z)
    )


def _mesh(z: Float32 = 0) raises -> RigidBody:
    return RigidBody(
        STATIC,
        Shape.mesh([_floor(z)]),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _same_hit(
    actual: Optional[SnapshotRaycastHit], expected: Optional[RaycastHit]
) raises:
    assert_equal(Bool(actual), Bool(expected))
    if Bool(expected):
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


def _same_snapshot_hit(
    actual: Optional[SnapshotRaycastHit], expected: Optional[SnapshotRaycastHit]
) raises:
    assert_equal(Bool(actual), Bool(expected))
    if Bool(expected):
        assert_true(actual.value().owner == expected.value().owner)
        assert_true(actual.value().distance == expected.value().distance)
        assert_true(actual.value().point == expected.value().point)
        assert_true(actual.value().normal == expected.value().normal)
        assert_equal(
            actual.value().material.friction, expected.value().material.friction
        )
        assert_equal(
            actual.value().material.restitution,
            expected.value().material.restitution,
        )


def _brute(
    world: PhysicsWorld,
    origin: Vector3,
    direction: Vector3,
    reach: Length,
    ignore: BodyId,
) raises -> Optional[RaycastHit]:
    # No bounds, index, candidate list or snapshot helper. Every primitive
    # reaches the old world's exact narrow phase, in historical body order.
    var ray = Ray(origin, direction)
    var best: Optional[RaycastHit] = None
    for t in range(len(world._triangles)):
        best = world._triangle_hit(ray, t, reach.value, best, ignore)
    for i in range(len(world.bodies)):
        if i == ignore.value or world.bodies[i].shape.kind == MESH:
            continue
        if not world.bodies[i].collides:
            continue
        var hit = world._shape_hit(ray, i)
        if not Bool(hit):
            continue
        if hit.value().distance > reach.value:
            continue
        if Bool(best) and best.value().distance <= hit.value().distance:
            continue
        best = hit
    return best


def _compare(
    snapshot: PhysicsQuerySnapshot,
    world: PhysicsWorld,
    origin: Vector3,
    direction: Vector3,
    reach: Float32 = 1000,
    ignore: BodyId = BodyId(-1),
) raises:
    var actual = snapshot.raycast(origin, direction, Length(reach), ignore)
    _same_hit(actual, world.raycast(origin, direction, Length(reach), ignore))
    _same_hit(actual, _brute(world, origin, direction, Length(reach), ignore))
    if Bool(actual):
        snapshot.check_owner(actual.value().owner)


def test_empty_disabled_and_singleton_snapshots() raises:
    var world = PhysicsWorld()
    var empty = PhysicsQuerySnapshot(world)
    _compare(empty, world, Vector3(0, 0, 3), Vector3(0, 0, -1))
    var body = _body(0)
    body.collides = False
    _ = world.add_body(body^)
    var disabled = PhysicsQuerySnapshot(world)
    _compare(disabled, world, Vector3(0, 0, 3), Vector3(0, 0, -1))
    world.bodies[0].collides = True
    var enabled = PhysicsQuerySnapshot(world)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    assert_false(Bool(empty.raycast(origin, direction, Length(10), BodyId(-1))))
    assert_false(
        Bool(disabled.raycast(origin, direction, Length(10), BodyId(-1)))
    )
    _compare(enabled, world, origin, direction)
    assert_equal(
        enabled.raycast(origin, direction, Length(10), BodyId(-1))
        .value()
        .distance.value,
        Float32(2.5),
    )


def test_snapshot_distance_keeps_length_units_and_live_scalar_compatibility() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(0))
    var snapshot = PhysicsQuerySnapshot(world)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var hit = snapshot.raycast(
        origin, direction, Length(10), BodyId(-1)
    ).value()
    var distance: Length = hit.distance
    assert_true(distance == Length(2.5))
    assert_equal(distance.to(CENTIMETER), Float32(250))
    var live: Float32 = (
        world.raycast(origin, direction, Length(10), BodyId(-1))
        .value()
        .distance
    )
    assert_equal(distance.value, live)


def test_all_primitives_modes_and_exact_narrow_phase_answers() raises:
    for kind in range(4):
        for mode in [STATIC, KINEMATIC, DYNAMIC]:
            var world = PhysicsWorld()
            var body = _body(kind)
            body.set_kind(mode)
            _ = world.add_body(body^)
            var snapshot = PhysicsQuerySnapshot(world)
            for origin in [
                Vector3(0, 0, 3),
                Vector3(3, 0, 0),
                Vector3(0, 3, 0),
                Vector3(-3, 0, 0),
                Vector3(0, 0, -3),
                Vector3(0, 0, 0),
                Vector3(0.5, 0.5, 3),
                Vector3(4, 4, 4),
            ]:
                for direction in [
                    Vector3(0, 0, -1),
                    Vector3(-1, 0, 0),
                    Vector3(0, -1, 0),
                    Vector3(1, 2, 3),
                ]:
                    _compare(snapshot, world, origin, direction)
            assert_true(
                Bool(
                    snapshot.raycast(
                        Vector3(0, 0, 3),
                        Vector3(0, 0, -1),
                        Length(10),
                        BodyId(-1),
                    )
                )
            )


def test_pose_local_transform_and_shape_edits_leave_capture_frozen() raises:
    for kind in range(4):
        for change in range(8):
            var world = PhysicsWorld()
            _ = world.add_body(_body(kind))
            var snapshot = PhysicsQuerySnapshot(world)
            var origin = Vector3(0, 0, 3)
            var direction = Vector3(0, 0, -1)
            var before = snapshot.raycast(
                origin, direction, Length(10), BodyId(-1)
            )
            assert_true(Bool(before))
            if change == 0:
                world.bodies[0].position = Vector3(20, 30, 40)
            elif change == 1:
                world.bodies[0].rotation = Quaternion.from_axis_angle(
                    Vector3(1, 0, 0), Angle(90, DEGREE)
                )
            elif change == 2:
                world.bodies[0].shape_position = Vector3(0, 0, 1)
            elif change == 3:
                world.bodies[0].shape_rotation = Quaternion.from_axis_angle(
                    Vector3(0, 1, 0), Angle(90, DEGREE)
                )
            elif change == 4:
                world.bodies[0].shape = Shape.sphere(Length(2))
            elif change == 5:
                if kind == 0 or kind == 2:
                    world.bodies[0].shape.radius = 1
                    world.bodies[0].shape.half_height = 2
                else:
                    # Change the existing nested buffers, not only the shape
                    # field. A shallow borrowed polyhedron would change too.
                    for i in range(
                        len(world.bodies[0].shape.polyhedron.vertices)
                    ):
                        world.bodies[0].shape.polyhedron.vertices[i].z *= 2
                    world.bodies[0].shape.polyhedron.normals[0] = Vector3(
                        0, 0, -1
                    )
                    world.bodies[0].shape.polyhedron.offsets[0] = 2
            elif change == 6:
                world.bodies[0].material = PhysicsMaterial(0.9, 0.8)
            else:
                world.bodies[0].set_kind(KINEMATIC)
                world.bodies[0].collides = False
            _same_snapshot_hit(
                snapshot.raycast(origin, direction, Length(10), BodyId(-1)),
                before,
            )
            _same_snapshot_hit(
                snapshot.raycast(origin, direction, Length(10), BodyId(-1)),
                before,
            )


def test_insertion_removal_replacement_and_independent_captures() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(0))
    var first = PhysicsQuerySnapshot(world)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var before = first.raycast(origin, direction, Length(10), BodyId(-1))
    _ = world.add_body(_body(0, Vector3(0, 0, 1)))
    var second = PhysicsQuerySnapshot(world)
    var later = second.raycast(origin, direction, Length(10), BodyId(-1))
    assert_equal(before.value().owner.source_body, BodyId(0))
    assert_equal(later.value().owner.source_body, BodyId(1))
    assert_equal(later.value().distance.value, Float32(1.5))
    assert_true(before.value().owner != later.value().owner)
    assert_true(before.value().owner.is_valid())
    var second_first = second.raycast(origin, direction, Length(10), BodyId(1))
    assert_true(second_first.value().owner != later.value().owner)
    with assert_raises():
        second.check_owner(before.value().owner)
    with assert_raises():
        first.check_owner(later.value().owner)
    world.bodies.clear()
    _ = world.add_body(_body(1, Vector3(0, 0, 1)))
    var replacement = PhysicsQuerySnapshot(world)
    var replaced = replacement.raycast(
        origin, direction, Length(10), BodyId(-1)
    )
    assert_equal(replaced.value().owner.source_body, BodyId(0))
    assert_true(replaced.value().owner != before.value().owner)
    _same_snapshot_hit(
        first.raycast(origin, direction, Length(10), BodyId(-1)), before
    )
    _same_snapshot_hit(
        second.raycast(origin, direction, Length(10), BodyId(-1)), later
    )
    with assert_raises():
        replacement.check_owner(before.value().owner)
    var invalid = before.value().owner
    invalid.source_body = BodyId(-1)
    assert_false(invalid.is_valid())
    with assert_raises():
        first.check_owner(invalid)
    invalid = before.value().owner
    invalid.source_body = BodyId(1)
    with assert_raises():
        first.check_owner(invalid)
    first.check_owner(before.value().owner)
    # Ignore ids use the captured historical slots, independent of live data.
    assert_false(Bool(first.raycast(origin, direction, Length(10), BodyId(0))))
    assert_equal(
        second.raycast(origin, direction, Length(10), BodyId(1))
        .value()
        .owner.source_body,
        BodyId(0),
    )


def _escaped_snapshot() raises -> PhysicsQuerySnapshot:
    var world = PhysicsWorld()
    _ = world.add_body(_body(3))
    return PhysicsQuerySnapshot(world)


def _escaped_hit() raises -> SnapshotRaycastHit:
    var snapshot = _escaped_snapshot()
    return snapshot.raycast(
        Vector3(0, 0, 3), Vector3(0, 0, -1), Length(10), BodyId(-1)
    ).value()


def test_source_destruction_moves_and_owner_tokens_do_not_alias() raises:
    var snapshot = _escaped_snapshot()
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var before = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
    var moved = snapshot^
    _same_snapshot_hit(
        moved.raycast(origin, direction, Length(10), BodyId(-1)), before
    )
    moved.check_owner(before.value().owner)
    var escaped = _escaped_hit()
    assert_equal(escaped.owner.source_body, BodyId(0))
    assert_equal(escaped.distance.value, Float32(2))
    # Retained hit owners keep their capture token alive across destruction.
    for _ in range(32):
        var fresh = _escaped_snapshot()
        var fresh_hit = fresh.raycast(origin, direction, Length(10), BodyId(-1))
        assert_true(fresh_hit.value().owner != escaped.owner)
        with assert_raises():
            fresh.check_owner(escaped.owner)


def test_mesh_first_ties_body_ties_ignore_and_closed_reach() raises:
    for clean in [False, True]:
        var world = PhysicsWorld()
        _ = world.add_body(_body(0, Vector3(0, 0, -0.5)))
        _ = world.add_body(_body(0, Vector3(0, 0, -0.5)))
        _ = world.add_body(_mesh())
        for i in range(32):
            _ = world.add_body(_body(0, Vector3(100 + Float32(i) * 4, 100, 0)))
        if clean:
            world._rebuild()
        var snapshot = PhysicsQuerySnapshot(world)
        assert_true(len(snapshot._index.nodes) > 0)
        var origin = Vector3(0, 0, 2)
        var direction = Vector3(0, 0, -1)
        for reach in [
            Float32(-1),
            Float32(0),
            Float32(1.999),
            Float32(2),
            Float32(3),
        ]:
            for ignore in [
                BodyId(-1),
                BodyId(0),
                BodyId(1),
                BodyId(2),
                BodyId(999),
            ]:
                _compare(snapshot, world, origin, direction, reach, ignore)
        assert_equal(
            snapshot.raycast(origin, direction, Length(2), BodyId(-1))
            .value()
            .owner.source_body,
            BodyId(2),
        )
        assert_equal(
            snapshot.raycast(origin, direction, Length(2), BodyId(2))
            .value()
            .owner.source_body,
            BodyId(0),
        )
        # The dirty flag selects only the existing mesh traversal strategy.
        assert_equal(world._dirty, not clean)


def test_registered_mesh_view_geometry_material_and_enablement_are_owned() raises:
    for clean in [False, True]:
        var world = PhysicsWorld()
        _ = world.add_body(_mesh())
        world.bodies[0].material = PhysicsMaterial(0.3, 0.2)
        if clean:
            world._rebuild()
        var snapshot = PhysicsQuerySnapshot(world)
        var origin = Vector3(0, 0, 3)
        var direction = Vector3(0, 0, -1)
        var before = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
        assert_equal(before.value().distance.value, Float32(3))
        world.bodies[0].position = Vector3(0, 0, 20)
        world.bodies[0].shape_position = Vector3(10, 0, 0)
        world.bodies[0].rotation = Quaternion.from_axis_angle(
            Vector3(1, 0, 0), Angle(90, DEGREE)
        )
        world.bodies[0].shape_rotation = Quaternion.from_axis_angle(
            Vector3(0, 1, 0), Angle(90, DEGREE)
        )
        world.bodies[0].shape.triangles[0] = _floor(5)
        world.bodies[0].shape = Shape.mesh([_floor(7)])
        # Public mesh edits do not replace insertion-time registered triangles.
        var after_edits = PhysicsQuerySnapshot(world)
        _compare(after_edits, world, origin, direction)
        assert_equal(
            after_edits.raycast(origin, direction, Length(10), BodyId(-1))
            .value()
            .distance.value,
            Float32(3),
        )
        world.bodies[0].material = PhysicsMaterial(0.9, 0.8)
        world.bodies[0].collides = False
        _ = world.add_body(_mesh(1))
        world._rebuild()
        _same_snapshot_hit(
            snapshot.raycast(origin, direction, Length(10), BodyId(-1)), before
        )
        world.bodies.clear()
        _same_snapshot_hit(
            snapshot.raycast(origin, direction, Length(10), BodyId(-1)), before
        )


def test_many_primitives_match_brute_force_in_all_distributions() raises:
    for distribution in range(4):
        var world = PhysicsWorld()
        for i in range(65):
            var at = Vector3(0, 0, 0)
            if distribution == 0:
                at = Vector3(Float32(i % 9) * 3, Float32(i // 9) * 3, 0)
            elif distribution == 1:
                at = Vector3(0, Float32(i % 9) * 3, Float32(i // 9) * 3)
            elif distribution == 2:
                at = Vector3(Float32(i % 5) * 10 + Float32(i % 3) * 0.2, 0, 0)
            var body = _body(i % 4, at)
            if i % 3 == 0:
                body.set_kind(STATIC)
            elif i % 3 == 1:
                body.set_kind(KINEMATIC)
            body.rotation = Quaternion.from_axis_angle(
                Vector3(0, 0, 1), Angle(Float32(i % 7) * 13, DEGREE)
            )
            body.shape_position = Vector3(Float32(i % 3) * 0.1, 0, 0)
            body.shape_rotation = Quaternion.from_axis_angle(
                Vector3(0, 1, 0), Angle(Float32(i % 5) * 7, DEGREE)
            )
            body.collides = i % 11 != 0
            _ = world.add_body(body^)
        var snapshot = PhysicsQuerySnapshot(world)
        for i in range(64):
            var origin = Vector3(Float32(i % 8) * 3, Float32(i // 8) * 3, 30)
            for direction in [
                Vector3(0, 0, -1),
                Vector3(-1, 0, -1),
                Vector3(0, 1, -1),
            ]:
                _compare(snapshot, world, origin, direction)
                _compare(snapshot, world, origin, direction, 29, BodyId(i))
        _compare(snapshot, world, Vector3(1000, 1000, 1000), Vector3(1, 0, 0))


def test_axis_queries_mix_exact_and_rotated_shapes_without_changing_ties() raises:
    var world = PhysicsWorld()
    for i in range(65):
        var body = _body(
            i % 4, Vector3(Float32(i % 13) * 4, Float32(i // 13) * 4, 0)
        )
        if i % 5 == 0:
            # An exact unit quaternion that permutes axes without rounding.
            body.shape_rotation = Quaternion(0.5, 0.5, 0.5, 0.5)
        elif i % 5 == 1:
            body.rotation = Quaternion(0.5, 0.5, 0.5, -0.5)
        elif i % 5 == 2:
            body.rotation = Quaternion.from_axis_angle(
                Vector3(0, 1, 0), Angle(17, DEGREE)
            )
        elif i % 5 == 3:
            body.shape_rotation = Quaternion.from_axis_angle(
                Vector3(1, 0, 0), Angle(31, DEGREE)
            )
        _ = world.add_body(body^)
    # Same-distance ordinary and rotated shapes require global body-slot
    # order even if an implementation uses different candidate sources.
    for i in range(12):
        var body = _body(
            0 if i % 2 == 0 else 1,
            Vector3(100, 0, Float32(0) if i % 2 == 0 else Float32(-0.5)),
        )
        if i % 2 == 1:
            body.rotation = Quaternion.from_axis_angle(
                Vector3(0, 0, 1), Angle(17, DEGREE)
            )
        _ = world.add_body(body^)
    var unsafe_first = _body(1, Vector3(104, 0, -0.5))
    unsafe_first.rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(17, DEGREE)
    )
    _ = world.add_body(unsafe_first^)
    _ = world.add_body(_body(0, Vector3(104, 0, 0)))
    var snapshot = PhysicsQuerySnapshot(world)
    assert_true(len(snapshot._index.nodes) > 0)
    for i in range(65):
        var at = world.bodies[i].position
        for direction in [
            Vector3(1, 0, 0),
            Vector3(-1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, -1, 0),
            Vector3(0, 0, 1),
            Vector3(0, 0, -1),
        ]:
            for origin in [at - direction * 3, at, at + direction * 3]:
                _compare(snapshot, world, origin, direction, 3)
                _compare(snapshot, world, origin, direction, 3, BodyId(i))
    _compare(snapshot, world, Vector3(100, 0, 3), Vector3(0, 0, -1))
    _compare(
        snapshot, world, Vector3(100, 0, 3), Vector3(0, 0, -1), 10, BodyId(65)
    )
    _compare(snapshot, world, Vector3(104, 0, 3), Vector3(0, 0, -1))
    _compare(
        snapshot, world, Vector3(104, 0, 3), Vector3(0, 0, -1), 10, BodyId(77)
    )


def test_axis_round_boundaries_huge_origins_and_small_or_large_radii() raises:
    for radius in [
        Float32(2.0**-17),
        Float32(2.0**-16),
        Float32(0.5),
        Float32(2.0**16),
        Float32(2.0**17),
    ]:
        var world = PhysicsWorld()
        for i in range(33):
            var body = _body(
                0, Vector3(Float32(i) * max(Float32(4), radius * 4), 0, 0)
            )
            body.shape.radius = radius
            _ = world.add_body(body^)
        var capsule = _body(2, Vector3(0, 0, -10 * radius))
        capsule.shape.radius = radius
        capsule.shape.half_height = 0
        _ = world.add_body(capsule^)
        var snapshot = PhysicsQuerySnapshot(world)
        assert_equal(
            len(snapshot._index.nodes) > 0,
            radius >= 0.0000152587890625 and radius <= 65536,
        )
        for sign in [Float32(-1), Float32(1)]:
            for transverse in [Float32(0), radius, radius * 2]:
                var origin = Vector3(
                    0, transverse, sign * max(Float32(3), radius * 3)
                )
                _compare(snapshot, world, origin, Vector3(0, 0, -sign), 1e30)
            for extreme in [Float32(1e12), Float32(1.000001e12)]:
                _compare(
                    snapshot,
                    world,
                    Vector3(0, 0, sign * extreme),
                    Vector3(0, 0, -sign),
                    2e30,
                )
    var boundary_world = PhysicsWorld()
    for i in range(33):
        _ = boundary_world.add_body(_body(0, Vector3(Float32(i) * 4, 0, 0)))
    var boundary_snapshot = PhysicsQuerySnapshot(boundary_world)
    assert_true(len(boundary_snapshot._index.nodes) > 0)
    for y in [
        Float32(-0.5000000596046448),
        Float32(-0.5),
        Float32(0.5),
        Float32(0.5000000596046448),
    ]:
        _compare(
            boundary_snapshot,
            boundary_world,
            Vector3(0, y, 3),
            Vector3(0, 0, -1),
            3,
        )


def test_returned_hit_fields_are_independent_values() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(1))
    var snapshot = PhysicsQuerySnapshot(world)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var before = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
    var edited = before.value()
    edited.point = Vector3(10, 20, 30)
    edited.normal = Vector3(1, 0, 0)
    edited.distance = Length(90)
    edited.material = PhysicsMaterial(0.9, 0.8)
    edited.owner.source_body = BodyId(99)
    assert_equal(edited.distance.value, Float32(90))
    _same_snapshot_hit(
        snapshot.raycast(origin, direction, Length(10), BodyId(-1)), before
    )
    snapshot.check_owner(before.value().owner)


def test_indexed_capture_owns_geometry_after_bulk_source_destruction() raises:
    var world = PhysicsWorld()
    for i in range(64):
        _ = world.add_body(_body(i % 4, Vector3(Float32(i) * 4, 0, 0)))
    var snapshot = PhysicsQuerySnapshot(world)
    assert_true(len(snapshot._index.nodes) > 0)
    var before = List[Optional[SnapshotRaycastHit]]()
    for i in range(64):
        var hit = snapshot.raycast(
            Vector3(Float32(i) * 4, 0, 3),
            Vector3(0, 0, -1),
            Length(10),
            BodyId(-1),
        )
        assert_true(Bool(hit))
        assert_equal(hit.value().owner.source_body, BodyId(i))
        before.append(hit)
    for i in range(64):
        world.bodies[i].position.y = 20
        world.bodies[i].shape_position = Vector3(10, 20, 30)
        world.bodies[i].material = PhysicsMaterial(0.9, 0.8)
        world.bodies[i].collides = False
        world.bodies[i].shape.polyhedron.vertices.clear()
        world.bodies[i].shape.polyhedron.normals.clear()
        world.bodies[i].shape.radius = 10
    world.bodies.clear()
    for i in range(64):
        _same_snapshot_hit(
            snapshot.raycast(
                Vector3(Float32(i) * 4, 0, 3),
                Vector3(0, 0, -1),
                Length(10),
                BodyId(-1),
            ),
            before[i],
        )


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite^.run()
