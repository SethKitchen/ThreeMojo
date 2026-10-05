# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Snapshot validation refuses malformed capture inputs before indexed reads."""

from extensions.physics.body import BodyId, BodyKind, STATIC
from extensions.physics.query_snapshot import (
    PhysicsQuerySnapshot,
    _admitted_axes,
)
from extensions.physics.primitive_index import _PrimitiveIndex
from extensions.physics.collide import WorldShape
from extensions.physics.shape import ShapeKind
from extensions.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.ray import Ray
from math.vector3 import Vector3
from std.math import inf, isnan, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_physics_query_snapshot import (
    _body,
    _compare,
    _floor,
    _mesh,
    _same_snapshot_hit,
)
from units.si import Length


def test_invalid_modes_kinds_and_materials_are_refused() raises:
    for disabled in [False, True]:
        for change in range(10):
            var world = PhysicsWorld()
            _ = world.add_body(_body(0))
            world.bodies[0].collides = not disabled
            if change == 0:
                world.bodies[0]._kind = BodyKind(-1)
            elif change == 1:
                world.bodies[0].shape.kind = ShapeKind(-1)
            elif change == 2:
                world.bodies[0].shape.kind = ShapeKind(5)
            elif change == 3:
                world.bodies[0].material.friction = -1
            elif change == 4:
                world.bodies[0].material.friction = nan[DType.float32]()
            elif change == 5:
                world.bodies[0].material.friction = inf[DType.float32]()
            elif change == 6:
                world.bodies[0].material.restitution = -1
            elif change == 7:
                world.bodies[0].material.restitution = 2
            elif change == 8:
                world.bodies[0].material.restitution = nan[DType.float32]()
            else:
                world.bodies[0].material.restitution = inf[DType.float32]()
            with assert_raises():
                _ = PhysicsQuerySnapshot(world)


def test_nonfinite_active_poses_and_nonunit_rotations_are_refused() raises:
    for value in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for change in range(6):
            var world = PhysicsWorld()
            _ = world.add_body(_body(1))
            if change == 0:
                world.bodies[0].position.x = value
            elif change == 1:
                world.bodies[0].position.y = value
            elif change == 2:
                world.bodies[0].position.z = value
            elif change == 3:
                world.bodies[0].shape_position.x = value
            elif change == 4:
                world.bodies[0].rotation.x = value
            else:
                world.bodies[0].shape_rotation.w = value
            with assert_raises():
                _ = PhysicsQuerySnapshot(world)
    for local in [False, True]:
        for q in [Quaternion(0, 0, 0, 0), Quaternion(0, 0, 0, 2)]:
            var world = PhysicsWorld()
            _ = world.add_body(_body(1))
            if local:
                world.bodies[0].shape_rotation = q
            else:
                world.bodies[0].rotation = q
            with assert_raises():
                _ = PhysicsQuerySnapshot(world)


def test_round_dimensions_and_transformed_overflow_are_refused() raises:
    for kind in [0, 2]:
        for value in [
            Float32(0),
            Float32(-1),
            nan[DType.float32](),
            inf[DType.float32](),
        ]:
            var world = PhysicsWorld()
            _ = world.add_body(_body(kind))
            world.bodies[0].shape.radius = value
            with assert_raises():
                _ = PhysicsQuerySnapshot(world)
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        var world = PhysicsWorld()
        _ = world.add_body(_body(2))
        world.bodies[0].shape.half_height = value
        with assert_raises():
            _ = PhysicsQuerySnapshot(world)
    # Finite inputs can overflow world transforms or the stored Float32 bounds.
    for change in range(3):
        var world = PhysicsWorld()
        var body = _body(0 if change != 2 else 2)
        body.set_kind(STATIC)
        _ = world.add_body(body^)
        world.bodies[0].position = Vector3(0, 0, 3e38)
        if change == 0:
            world.bodies[0].shape_position = Vector3(0, 0, 3e38)
        elif change == 1:
            world.bodies[0].shape.radius = 3e38
        else:
            world.bodies[0].shape.half_height = 3e38
        with assert_raises():
            _ = PhysicsQuerySnapshot(world)
    var valid = PhysicsWorld()
    _ = valid.add_body(_body(2))
    valid.bodies[0].shape.half_height = 0
    var snapshot = PhysicsQuerySnapshot(valid)
    _compare(snapshot, valid, Vector3(0, 0, 3), Vector3(0, 0, -1))


def test_malformed_polyhedron_storage_is_refused_before_transform() raises:
    for change in range(23):
        var world = PhysicsWorld()
        _ = world.add_body(_body(1))
        ref poly = world.bodies[0].shape.polyhedron
        if change == 0:
            poly.vertices.clear()
        elif change == 1:
            poly.normals.clear()
        elif change == 2:
            poly.offsets.clear()
        elif change == 3:
            poly.face_start.clear()
        elif change == 4:
            poly.face_start[0] = 1
        elif change == 5:
            poly.face_start[len(poly.face_start) - 1] -= 1
        elif change == 6:
            poly.vertices[0].x = nan[DType.float32]()
        elif change == 7:
            poly.normals[0].x = inf[DType.float32]()
        elif change == 8:
            poly.normals[0] = Vector3(0, 0, 0)
        elif change == 9:
            poly.offsets[0] = nan[DType.float32]()
        elif change == 10:
            poly.face_start[1] = -1
        elif change == 11:
            poly.face_start[1] = len(poly.face_corners) + 1
        elif change == 12:
            poly.face_start[1] = 2
        elif change == 13:
            poly.face_corners[0] = -1
        elif change == 14:
            poly.face_corners[0] = len(poly.vertices)
        elif change == 15:
            poly.edge_a.clear()
        elif change == 16:
            poly.edge_a[0] = -1
        elif change == 17:
            poly.edge_a[0] = len(poly.vertices)
        elif change == 18:
            poly.edge_b[0] = -1
        elif change == 19:
            poly.edge_b[0] = len(poly.vertices)
        elif change == 20:
            poly.face_start[2] = poly.face_start[1] - 1
        elif change == 21:
            poly.vertices[0].z = inf[DType.float32]()
        else:
            poly.offsets[0] = inf[DType.float32]()
        with assert_raises():
            _ = PhysicsQuerySnapshot(world)


def test_disabled_geometry_is_absent_and_reenable_requires_valid_capture() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(0))
    world.bodies[0].collides = False
    world.bodies[0].shape.radius = -1
    world.bodies[0].position.x = nan[DType.float32]()
    var disabled = PhysicsQuerySnapshot(world)
    assert_equal(disabled.body_count(), 1)
    assert_false(
        Bool(
            disabled.raycast(
                Vector3(0, 0, 3), Vector3(0, 0, -1), Length(10), BodyId(-1)
            )
        )
    )
    world.bodies[0].collides = True
    with assert_raises():
        _ = PhysicsQuerySnapshot(world)


def test_bad_registered_mesh_owners_and_triangles_are_refused() raises:
    for change in range(9):
        var world = PhysicsWorld()
        _ = world.add_body(_mesh())
        if change == 0:
            world._triangle_body.clear()
        elif change == 1:
            world._triangle_body[0] = -1
        elif change == 2:
            world._triangle_body[0] = 1
        elif change == 3:
            world.bodies[0] = _body(0)
        elif change == 4:
            world.bodies.clear()
        elif change == 5:
            world._triangles[0].a.x = nan[DType.float32]()
        elif change == 6:
            world._triangles[0].b.y = inf[DType.float32]()
        elif change == 7:
            world._triangles[0].c.z = -inf[DType.float32]()
        else:
            world._triangles.clear()
        with assert_raises():
            _ = PhysicsQuerySnapshot(world)


def test_query_validation_and_rejected_capture_preserve_prior_snapshot() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(0))
    var snapshot = PhysicsQuerySnapshot(world)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var before = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
    for empty in [False, True]:
        var source = PhysicsWorld()
        if not empty:
            _ = source.add_body(_body(0))
        var checked = PhysicsQuerySnapshot(source)
        with assert_raises():
            _ = checked.raycast(
                origin, Vector3(0, 0, 0), Length(10), BodyId(-1)
            )
        with assert_raises():
            _ = checked.raycast(origin, direction, Length(10), BodyId(-2))
        with assert_raises():
            _ = checked.raycast(
                origin, direction, Length(nan[DType.float32]()), BodyId(-1)
            )
        for value in [
            nan[DType.float32](),
            inf[DType.float32](),
            -inf[DType.float32](),
        ]:
            with assert_raises():
                _ = checked.raycast(
                    Vector3(value, 0, 3), direction, Length(10), BodyId(-1)
                )
            with assert_raises():
                _ = checked.raycast(
                    origin, Vector3(0, value, -1), Length(10), BodyId(-1)
                )
        _compare(checked, source, origin, direction, inf[DType.float32]())
        _compare(checked, source, origin, direction, -inf[DType.float32]())
    world.bodies[0].shape.radius = -1
    with assert_raises():
        _ = PhysicsQuerySnapshot(world)
    _same_snapshot_hit(
        snapshot.raycast(origin, direction, Length(10), BodyId(-1)), before
    )


def test_mesh_narrow_phase_rejection_and_closer_replacement() raises:
    for clean in [False, True]:
        var world = PhysicsWorld()
        _ = world.add_body(_mesh(-2))
        _ = world.add_body(_mesh(0))
        _ = world.add_body(_mesh(-1))
        _ = world.add_body(_body(0, Vector3(0, 0, 1)))
        if clean:
            world._rebuild()
        var snapshot = PhysicsQuerySnapshot(world)
        for origin in [Vector3(0, 0, 3), Vector3(20, 0, 3), Vector3(0, 0, -3)]:
            for reach in [Float32(0), Float32(2), Float32(3), Float32(10)]:
                for ignore in [BodyId(-1), BodyId(0), BodyId(1), BodyId(3)]:
                    _compare(
                        snapshot,
                        world,
                        origin,
                        Vector3(0, 0, -1),
                        reach,
                        ignore,
                    )
        var before = snapshot.raycast(
            Vector3(0, 0, 3), Vector3(0, 0, -1), Length(10), BodyId(3)
        )
        assert_true(Bool(before))
        # Force an actual source-buffer edit and octree rebuild. This tests
        # deep ownership, in addition to the public insertion-time mesh rule.
        world._triangles[1] = _floor(2)
        world._rebuild()
        _same_snapshot_hit(
            snapshot.raycast(
                Vector3(0, 0, 3), Vector3(0, 0, -1), Length(10), BodyId(3)
            ),
            before,
        )
        world.bodies[1].collides = False
        var disabled = PhysicsQuerySnapshot(world)
        _compare(
            disabled, world, Vector3(0, 0, 3), Vector3(0, 0, -1), 10, BodyId(3)
        )


def test_tight_bounds_cannot_cull_current_finite_narrow_phase_answers() raises:
    var world = PhysicsWorld()
    var body = _body(0, Vector3(1e8, 1e8, 0))
    body.shape.radius = 1
    _ = world.add_body(body^)
    var snapshot = PhysicsQuerySnapshot(world)
    var origin = Vector3(99999984, 99999984, 0)
    var direction = Vector3(1, 1.0000001, 0)
    var ray = Ray(origin, direction)
    # At this magnitude the Float32 radius disappears from x and y bounds.
    # The two normalized direction components are distinct, so the widened
    # slab test cannot meet both collapsed slabs at the same parameter.
    assert_equal(snapshot._boxes[0].min.x, snapshot._boxes[0].max.x)
    assert_equal(snapshot._boxes[0].min.y, snapshot._boxes[0].max.y)
    assert_false(ray.intersects_box(snapshot._boxes[0]))
    var index = _PrimitiveIndex()
    index.rebuild(snapshot._boxes)
    var found = List[Int]()
    _ = index.ray(ray, found)
    assert_equal(len(found), 0)
    var expected = world.raycast(origin, direction, Length(30), BodyId(-1))
    assert_true(Bool(expected))
    assert_true(expected.value().distance > 20)
    assert_true(expected.value().distance < 22)
    _compare(snapshot, world, origin, direction, 30)


def test_tight_bounds_cannot_cull_existing_nonfinite_kernel_results() raises:
    var world = PhysicsWorld()
    var body = _body(0)
    body.shape.radius = 1e20
    _ = world.add_body(body^)
    var snapshot = PhysicsQuerySnapshot(world)
    var origin = Vector3(2e20, 0, 0)
    var direction = Vector3(0, 0, 1)
    var ray = Ray(origin, direction)
    assert_false(ray.intersects_box(snapshot._boxes[0]))
    var expected = world.raycast(origin, direction, Length(10), BodyId(-1))
    var actual = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
    assert_true(Bool(expected))
    assert_true(Bool(actual))
    # Finite geometry reaches radius^2 - drop^2 = infinity - infinity in
    # the old Float32 sphere kernel. Preserve its Optional and IEEE result;
    # changing that kernel is a separate numerical contract correction.
    assert_true(isnan(expected.value().distance))
    assert_true(isnan(actual.value().distance))
    assert_true(isnan(expected.value().point.x))
    assert_true(isnan(actual.value().point.x))
    assert_true(isnan(actual.value().point.y))
    assert_true(isnan(actual.value().point.z))
    assert_equal(actual.value().owner.source_body, expected.value().body)
    assert_true(actual.value().normal == expected.value().normal)
    assert_equal(
        actual.value().material.friction, expected.value().material.friction
    )
    snapshot.check_owner(actual.value().owner)


def test_ray_solids_do_not_require_edge_lists() raises:
    var world = PhysicsWorld()
    _ = world.add_body(_body(1))
    world.bodies[0].shape.polyhedron.edge_a.clear()
    world.bodies[0].shape.polyhedron.edge_b.clear()
    var snapshot = PhysicsQuerySnapshot(world)
    _compare(snapshot, world, Vector3(0, 0, 3), Vector3(0, 0, -1))


def test_nonfinite_unsafe_results_keep_global_primitive_order() raises:
    for unsafe_first in [False, True]:
        var world = PhysicsWorld()
        var unsafe = _body(0, Vector3(1e25, 1e25, 0))
        unsafe.shape.radius = 1e20
        if unsafe_first:
            _ = world.add_body(unsafe.copy())
        for i in range(33):
            _ = world.add_body(_body(0, Vector3(Float32(i) * 4, 0, 0)))
        if not unsafe_first:
            _ = world.add_body(unsafe^)
        var snapshot = PhysicsQuerySnapshot(world)
        assert_true(len(snapshot._index.nodes) > 0)
        var origin = Vector3(0, 0, 3)
        var direction = Vector3(0, 0, -1)
        var expected = world.raycast(origin, direction, Length(10), BodyId(-1))
        var actual = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
        assert_true(Bool(expected))
        assert_true(Bool(actual))
        assert_equal(actual.value().owner.source_body, expected.value().body)
        if unsafe_first:
            _compare(snapshot, world, origin, direction, 10)
            assert_equal(actual.value().owner.source_body, BodyId(1))
        else:
            assert_true(isnan(expected.value().distance))
            assert_true(isnan(actual.value().distance))
            assert_equal(actual.value().owner.source_body, BodyId(33))


def test_numerical_admission_requires_the_proved_domain() raises:
    var zero = Vector3(0, 0, 0)
    for radius in [Float32(2.0**-16), Float32(0.5), Float32(2.0**16)]:
        assert_equal(_admitted_axes(WorldShape.round(zero, zero, radius)), 7)
    for radius in [Float32(2.0**-17), Float32(2.0**17)]:
        assert_equal(_admitted_axes(WorldShape.round(zero, zero, radius)), 0)
    assert_equal(
        _admitted_axes(WorldShape.round(Vector3(1e13, 0, 0), zero, 1)), 0
    )
    assert_equal(
        _admitted_axes(WorldShape.round(zero, Vector3(1e13, 0, 0), 1)), 0
    )
    assert_equal(_admitted_axes(WorldShape.round(zero, Vector3(1, 1, 0), 1)), 0)
    for axis in range(3):
        var end = Vector3(0, 0, 1)
        if axis == 0:
            end = Vector3(1, 0, 0)
        elif axis == 1:
            end = Vector3(0, 1, 0)
        assert_equal(_admitted_axes(WorldShape.round(zero, end, 1)), 1 << axis)
    var world = PhysicsWorld()
    _ = world.add_body(_body(1))
    var solid = world._shape(0)
    assert_equal(_admitted_axes(solid), 7)
    solid.polyhedron.normals[0] = solid.polyhedron.normals[0] * 2
    assert_equal(_admitted_axes(solid), 0)
    solid = world._shape(0)
    for i in range(len(solid.polyhedron.normals)):
        solid.polyhedron.normals[i] = Vector3(1, 0, 0)
    assert_equal(_admitted_axes(solid), 0)
    solid = world._shape(0)
    solid.polyhedron.vertices[0] = Vector3(0, -1e13, 0)
    assert_equal(_admitted_axes(solid), 0)


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite^.run()
