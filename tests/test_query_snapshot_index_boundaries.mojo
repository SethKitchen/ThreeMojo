# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact ray controls at snapshot index admission and merge boundaries."""

from extensions.physics.body import BodyId, RigidBody, STATIC
from extensions.physics.collide import WorldShape
from extensions.physics.shape import MESH, Polyhedron, Shape
from extensions.physics.query_snapshot import (
    PhysicsQuerySnapshot,
    _axis,
    _up,
    _admitted_axes,
)
from extensions.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.ray import Ray
from math.triangle import Triangle
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.test_physics_query_snapshot import _body, _mesh, _same_hit
from units.si import Length, Mass


def test_zero_vector_is_not_an_axis_and_rounding_is_outward() raises:
    assert_equal(_axis(Vector3(0, 0, 0)), -1)
    assert_equal(_up(0), bitcast[DType.float32](UInt32(1)))
    assert_equal(_up(-Float32(0)), bitcast[DType.float32](UInt32(1)))
    assert_true(_up(-1) > -1)
    assert_true(_up(1) > 1)


def test_empty_solid_is_not_admitted_to_any_axis() raises:
    var solid = WorldShape.solid(Polyhedron())
    assert_equal(_admitted_axes(solid), 0)
    solid.polyhedron.vertices.append(Vector3(0, 0, 0))
    assert_equal(_admitted_axes(solid), 0)


def test_empty_mesh_capture_returns_no_hit_without_mutation() raises:
    var world = PhysicsWorld()
    var body = RigidBody(
        STATIC,
        Shape(MESH),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    _ = world.add_body(body^)
    assert_true(world._dirty)
    var snapshot = PhysicsQuerySnapshot(world)
    assert_equal(snapshot.body_count(), 1)
    var origin = Vector3(0, 0, 3)
    var direction = Vector3(0, 0, -1)
    var actual = snapshot.raycast(origin, direction, Length(10), BodyId(-1))
    _same_hit(actual, world.raycast(origin, direction, Length(10), BodyId(-1)))
    assert_false(Bool(actual))
    assert_true(world._dirty)
    assert_equal(len(world.bodies), 1)
    assert_equal(len(world.bodies[0].shape.triangles), 0)
    assert_equal(world.bodies[0].mass(), Float32(0))
    assert_equal(world.bodies[0].kind(), STATIC)
    assert_equal(snapshot.body_count(), 1)


def test_complete_overlap_uses_owned_linear_answers() raises:
    var world = PhysicsWorld()
    for _ in range(33):
        _ = world.add_body(_body(0))
    var snapshot = PhysicsQuerySnapshot(world)
    assert_equal(len(snapshot._index.nodes), 0)
    var ray = Ray(Vector3(0, 0, 3), Vector3(0, 0, -1))
    _same_hit(
        snapshot.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
        world.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
    )


def test_mixed_axis_candidates_merge_once_in_body_order() raises:
    var world = PhysicsWorld()
    # The x-axis capsule belongs to the z-ray's linear list, but its
    # conservative round box also appears in the z-axis candidate list.
    var capsule = _body(2, Vector3(0, 0, 1))
    capsule.shape_rotation = Quaternion(0.5, 0.5, 0.5, 0.5)
    _ = world.add_body(capsule^)
    for i in range(32):
        _ = world.add_body(_body(0, Vector3(Float32(i) * 4, 0, 0)))
    var snapshot = PhysicsQuerySnapshot(world)
    assert_true(len(snapshot._index.nodes) > 0)
    assert_equal(len(snapshot._axis_linear[2]), 1)
    var ray = Ray(Vector3(0, 0, 4), Vector3(0, 0, -1))
    var actual = snapshot.raycast(
        ray.origin, ray.direction, Length(10), BodyId(-1)
    )
    _same_hit(
        actual, world.raycast(ray.origin, ray.direction, Length(10), BodyId(-1))
    )
    assert_true(Bool(actual))
    assert_equal(actual.value().owner.source_body.value, 0)
    ray = Ray(Vector3(4, 0, 4), Vector3(0, 0, -1))
    _same_hit(
        snapshot.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
        world.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
    )

    ray = Ray(Vector3(0, 0, 4), Vector3(0.1, 0, -1))
    _same_hit(
        snapshot.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
        world.raycast(ray.origin, ray.direction, Length(10), BodyId(-1)),
    )


def test_dense_axis_candidates_use_owned_linear_answers() raises:
    var world = PhysicsWorld()
    for i in range(32):
        _ = world.add_body(_body(0, Vector3(0, 0, Float32(i) * 4)))
    var snapshot = PhysicsQuerySnapshot(world)
    assert_true(len(snapshot._index.nodes) > 0)
    var ray = Ray(Vector3(0, 0, -3), Vector3(0, 0, 1))
    var candidates = List[Int]()
    _ = snapshot._index.axis_line(ray.origin, 2, candidates)
    assert_equal(len(candidates), 32)
    _same_hit(
        snapshot.raycast(ray.origin, ray.direction, Length(200), BodyId(-1)),
        world.raycast(ray.origin, ray.direction, Length(200), BodyId(-1)),
    )


def test_clean_mesh_octree_miss_is_empty() raises:
    var world = PhysicsWorld()
    var mesh = _mesh()
    mesh.shape.triangles.clear()
    for i in range(16):
        var x = Float32(i) * 4
        mesh.shape.triangles.append(
            Triangle(Vector3(x, 0, 0), Vector3(x + 1, 0, 0), Vector3(x, 1, 0))
        )
    _ = world.add_body(mesh^)
    world._rebuild()
    var snapshot = PhysicsQuerySnapshot(world)
    var ray = Ray(Vector3(100, 100, 3), Vector3(0, 0, -1))
    assert_equal(len(snapshot._octree.ray_triangles(ray)), 0)
    var actual = snapshot.raycast(
        ray.origin, ray.direction, Length(10), BodyId(-1)
    )
    _same_hit(
        actual, world.raycast(ray.origin, ray.direction, Length(10), BodyId(-1))
    )
    assert_false(Bool(actual))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
