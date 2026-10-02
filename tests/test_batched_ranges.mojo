# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded batched-geometry reservations and empty compaction."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from objects.instanced_mesh import BatchedMesh
from std.testing import TestSuite, assert_equal, assert_raises


def triangle(indexed: Bool) raises -> BufferGeometry:
    """Return a three-vertex geometry, with an optional index."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    if indexed:
        geometry.set_index([0, 1, 2])
    return geometry^


def test_empty_compaction_reclaims_every_reserved_slot() raises:
    for indexed in [False, True]:
        var geometry = triangle(indexed)
        var batch = BatchedMesh(
            MaterialId(0), NodeId(0), max_vertex_count=6, max_index_count=6
        )
        _ = batch.add_geometry(GeometryId(0), geometry, 6, 6)
        batch.delete_geometry(GeometryId(0))
        batch.optimize()
        assert_equal(batch.unused_vertex_count(), 6)
        assert_equal(batch.unused_index_count(), 6)
        _ = batch.add_geometry(GeometryId(1), geometry, 6, 6)
        assert_equal(batch.get_geometry_range_at(GeometryId(1)).vertex_start, 0)
        batch.optimize()
        assert_equal(batch.unused_vertex_count(), 0)


def test_vertex_reservation_checks_before_addition() raises:
    var geometry = triangle(False)
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    _ = batch.add_geometry(GeometryId(0), geometry)
    with assert_raises(contains="does not fit"):
        _ = batch.add_geometry(GeometryId(1), geometry, Int.MAX)
    assert_equal(batch.next_vertex_start, 3)
    assert_equal(len(batch.geometries), 1)
    _ = batch.add_geometry(GeometryId(1), geometry, Int.MAX - 3)
    assert_equal(batch.unused_vertex_count(), 0)
    with assert_raises(contains="does not fit"):
        _ = batch.add_geometry(GeometryId(2), geometry)


def test_index_reservation_checks_before_addition() raises:
    var geometry = triangle(True)
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    _ = batch.add_geometry(GeometryId(0), geometry)
    with assert_raises(contains="does not fit"):
        _ = batch.add_geometry(GeometryId(1), geometry, 3, Int.MAX)
    assert_equal(batch.next_index_start, 3)
    assert_equal(batch.next_vertex_start, 3)
    assert_equal(len(batch.geometries), 1)
    _ = batch.add_geometry(GeometryId(1), geometry, 3, Int.MAX - 3)
    assert_equal(batch.unused_index_count(), 0)
    with assert_raises(contains="does not fit"):
        _ = batch.add_geometry(GeometryId(2), geometry)


def test_empty_batch_resize_refuses_negative_limits() raises:
    var batch = BatchedMesh(
        MaterialId(0), NodeId(0), max_vertex_count=3, max_index_count=3
    )
    for counts in [(-1, 3), (3, -1), (-1, -1)]:
        with assert_raises(contains="negative count"):
            batch.set_geometry_size(counts[0], counts[1])
        assert_equal(batch.max_vertex_count, 3)
        assert_equal(batch.max_index_count, 3)
    batch.set_geometry_size(0, 0)
    batch.optimize()
    assert_equal(batch.unused_vertex_count(), 0)
    assert_equal(batch.unused_index_count(), 0)


def test_large_valid_range_resizes_without_wrapping() raises:
    var geometry = triangle(True)
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    _ = batch.add_geometry(GeometryId(0), geometry, Int.MAX, Int.MAX)
    batch.set_geometry_size(Int.MAX, Int.MAX)
    with assert_raises(contains="vertices it uses"):
        batch.set_geometry_size(Int.MAX - 1, Int.MAX)
    with assert_raises(contains="indices it uses"):
        batch.set_geometry_size(Int.MAX, Int.MAX - 1)
    batch.delete_geometry(GeometryId(0))
    batch.optimize()
    assert_equal(batch.unused_vertex_count(), Int.MAX)
    assert_equal(batch.unused_index_count(), Int.MAX)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
