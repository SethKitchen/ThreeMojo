# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Overflow-safe geometry ranges, groups, and tangent traversal."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _shape(indexed: Bool = False) raises -> BufferGeometry:
    """Return two triangles, with matching normals and texture coordinates."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute(
            [0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 0, 3, 0, 0, 2, 1, 0], 3
        ),
    )
    geometry.set_attribute(
        NORMAL,
        BufferAttribute(
            [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3
        ),
    )
    geometry.set_attribute(
        UV, BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 2)
    )
    if indexed:
        geometry.set_index([0, 1, 2, 3, 4, 5])
    return geometry^


def _expect(run: Tuple[Int, Int], first: Int, count: Int) raises:
    """Check a run's first slot and count separately."""
    assert_equal(run[0], first)
    assert_equal(run[1], count)


def _safe_to_traverse(mut geometry: BufferGeometry) raises:
    """Fail on the old overflow before testing any large-range traversal."""
    geometry.set_draw_range(1, Int.MAX)
    _expect(geometry.drawn_vertices(), 1, 5)
    geometry.set_draw_range(0)


def test_large_draw_ranges_stay_inside_the_stream() raises:
    for indexed in [False, True]:
        var geometry = _shape(indexed)
        geometry.set_draw_range(1, Int.MAX)
        _expect(geometry.drawn_vertices(), 1, 5)
        _expect(geometry.drawn_run(3, Int.MAX), 3, 1)
        geometry.set_draw_range(3, Int.MAX)
        _expect(geometry.drawn_vertices(), 3, 3)
        _expect(geometry.drawn_run(0, -1), 3, 1)
        _expect(geometry.drawn_run(0, 6), 3, 1)
        geometry.set_draw_range(Int.MAX, Int.MAX)
        _expect(geometry.drawn_vertices(), 6, 0)
        _expect(geometry.drawn_run(0, -1), 6, 0)
        geometry.set_draw_range(Int.MAX)
        _expect(geometry.drawn_vertices(), 6, 0)
        _expect(geometry.drawn_run(0, -1), 6, 0)


def test_large_group_runs_clamp_without_overflow() raises:
    var geometry = _shape()
    _expect(geometry.triangle_run(3, Int.MAX), 3, 1)
    _expect(geometry.triangle_run(Int.MAX, Int.MAX), 6, 0)
    _expect(geometry.triangle_run(0, -1), 0, 2)
    _expect(geometry.triangle_run(3, -1), 3, 1)
    for start in [0, 1, 3, 6, Int.MAX]:
        for count in [0, 1, 3, 6, Int.MAX]:
            var run = geometry.triangle_run(start, count)
            assert_true(run[0] >= 0 and run[0] <= 6)
            assert_true(run[1] >= 0 and run[1] <= (6 - run[0]) // 3)
            geometry.set_draw_range(start, count)
            var vertices = geometry.drawn_vertices()
            assert_true(vertices[0] >= 0 and vertices[0] <= 6)
            assert_true(vertices[1] >= 0 and vertices[1] <= 6 - vertices[0])
            for group_start in [0, 3, Int.MAX]:
                var intersection = geometry.drawn_run(group_start, count)
                assert_true(intersection[0] >= 0 and intersection[0] <= 6)
                assert_true(
                    intersection[1] >= 0
                    and intersection[1] <= (6 - intersection[0]) // 3
                )


def test_empty_stream_has_empty_large_ranges() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    geometry.set_draw_range(Int.MAX, Int.MAX)
    _expect(geometry.drawn_vertices(), 0, 0)
    _expect(geometry.drawn_run(Int.MAX, Int.MAX), 0, 0)
    _expect(geometry.triangle_run(Int.MAX, Int.MAX), 0, 0)


def test_group_extraction_checks_the_span_before_iterating() raises:
    var geometry = _shape()
    _safe_to_traverse(geometry)
    var material = MaterialIndex(0)
    assert_equal(
        geometry.group_part(GeometryGroup(3, 3, material)).vertex_count(), 3
    )
    assert_equal(
        geometry.group_part(GeometryGroup(6, 0, material)).vertex_count(), 0
    )
    for group in [
        GeometryGroup(-1, 3, material),
        GeometryGroup(0, -1, material),
        GeometryGroup(7, 0, material),
        GeometryGroup(3, 4, material),
        GeometryGroup(3, Int.MAX, material),
    ]:
        with assert_raises(contains="inside the triangle stream"):
            _ = geometry.group_part(group)


def test_empty_geometry_keeps_empty_group_extraction() raises:
    var geometry = BufferGeometry()
    var part = geometry.group_part(GeometryGroup(0, 0, MaterialIndex(0)))
    assert_equal(len(part.names), 0)
    for group in [
        GeometryGroup(-1, 0, MaterialIndex(0)),
        GeometryGroup(0, -1, MaterialIndex(0)),
        GeometryGroup(0, 1, MaterialIndex(0)),
        GeometryGroup(1, Int.MAX, MaterialIndex(0)),
    ]:
        with assert_raises(contains="inside the triangle stream"):
            _ = geometry.group_part(group)


def test_tangents_visit_only_bounded_group_slots() raises:
    for indexed in [False, True]:
        var geometry = _shape(indexed)
        _safe_to_traverse(geometry)
        geometry.add_group(3, Int.MAX)
        geometry.compute_tangents()
        ref tangent = geometry.attribute_view(TANGENT)
        assert_equal(tangent.component(0, 3), 0)
        for vertex in range(3, 6):
            assert_equal(tangent.component(vertex, 0), 1)
            assert_equal(tangent.component(vertex, 3), 1)
        geometry.clear_groups()
        geometry.add_group(Int.MAX, Int.MAX)
        geometry.compute_tangents()
        assert_equal(geometry.attribute_view(TANGENT).component(0, 3), 0)


def test_tangents_refuse_negative_group_spans() raises:
    var geometry = _shape()
    _safe_to_traverse(geometry)
    for group in [
        GeometryGroup(-1, 3, MaterialIndex(0)),
        GeometryGroup(0, -1, MaterialIndex(0)),
    ]:
        geometry.groups = [group]
        with assert_raises(contains="negative distance"):
            geometry.compute_tangents()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
