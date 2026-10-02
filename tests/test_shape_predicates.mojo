# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact signs and boundary predicates for the stored Float32 domain."""

from geometries.shape import (
    _BoundaryEdge,
    _append_edges,
    _corners,
    _edges_meet,
    _side,
    _sweep_on_y,
)
from math.vector2 import Vector2
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_orientation_is_exact_across_the_float32_exponent_range() raises:
    for scale in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]:
        var a = Vector2(-scale, -scale)
        var b = Vector2(scale, -scale)
        var c = Vector2(scale, scale)
        assert_equal(_side(a, b, c), 1)
        assert_equal(_side(c, b, a), -1)
        assert_equal(_side(a, Vector2(0, 0), c), 0)


def test_orientation_matches_an_independent_small_integer_oracle() raises:
    var points = List[Vector2]()
    for x in range(-1, 2):
        for y in range(-1, 2):
            points.append(Vector2(Float32(x), Float32(y)))
    for a in points:
        for b in points:
            for c in points:
                var determinant = (Int(b.x) - Int(a.x)) * (
                    Int(c.y) - Int(a.y)
                ) - (Int(b.y) - Int(a.y)) * (Int(c.x) - Int(a.x))
                var sign = Int(determinant > 0) - Int(determinant < 0)
                assert_equal(_side(a, b, c), sign)


def test_orientation_keeps_cancellation_and_translation_signs() raises:
    # Direct Float64 differences lose these small terms. The exact
    # homogeneous determinant is tiny * (1 - huge), strictly negative.
    var a = Vector2(1e30, 1e30)
    var b = Vector2(1, 1)
    var c = Vector2(0, 1e-30)
    assert_equal(_side(a, b, c), -1)
    assert_equal(_side(a, c, b), 1)
    for offset in [Float32(-8000000), Float32(0), Float32(8000000)]:
        a = Vector2(offset, offset)
        b = Vector2(offset + 2, offset + 1)
        c = Vector2(offset + 3, offset + 2)
        assert_equal(_side(a, b, c), 1)
        c = Vector2(offset + 4, offset + 2)
        assert_equal(_side(a, b, c), 0)


def test_segment_contacts_use_exact_sides_with_closed_boxes() raises:
    var diagonal = _BoundaryEdge(Vector2(0, 0), Vector2(2, 2), 0)
    assert_true(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(0, 2), Vector2(2, 0), 1))
    )
    assert_true(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(1, 1), Vector2(2, 0), 1))
    )
    assert_true(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(2, 0), Vector2(1, 1), 1))
    )
    assert_true(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(1, 1), Vector2(3, 3), 1))
    )
    assert_true(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(2, 2), Vector2(3, 0), 1))
    )
    assert_false(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(1, 4), Vector2(4, 1), 1))
    )
    assert_false(
        _edges_meet(diagonal, _BoundaryEdge(Vector2(0, 1), Vector2(1, 2), 1))
    )


def test_nonfinite_points_never_reach_the_exact_predicate() raises:
    for bad in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        for axis in range(2):
            var point = Vector2(bad, 1) if axis == 0 else Vector2(1, bad)
            var points: List[Vector2] = [
                Vector2(1, 1),
                Vector2(2, 1),
                point,
                Vector2(1, 1),
            ]
            with assert_raises():
                _ = _corners(points)


def test_a_boundary_append_with_no_runs_keeps_the_edge_list_empty() raises:
    var edges = List[_BoundaryEdge]()
    _append_edges(edges, List[Vector2](), 0)
    _append_edges(edges, [Vector2(0, 0)], 0)
    assert_equal(len(edges), 0)
    _append_edges(edges, [Vector2(0, 0), Vector2(1, 1)], 0)
    assert_equal(len(edges), 1)


def test_sweep_axis_minimizes_relative_interval_span() raises:
    var edges = List[_BoundaryEdge]()
    assert_false(_sweep_on_y(edges))
    edges.append(_BoundaryEdge(Vector2(0, 0), Vector2(10, 0), 0))
    assert_false(_sweep_on_y(edges))
    edges.append(_BoundaryEdge(Vector2(0, 1), Vector2(10, 1), 1))
    assert_true(_sweep_on_y(edges))
    edges = List[_BoundaryEdge]()
    edges.append(_BoundaryEdge(Vector2(0, 0), Vector2(0, 10), 0))
    edges.append(_BoundaryEdge(Vector2(1, 0), Vector2(1, 10), 1))
    assert_false(_sweep_on_y(edges))


def test_short_closed_contours_are_refused_before_reading_points() raises:
    var points = List[Vector2]()
    for _ in range(4):
        with assert_raises():
            _ = _corners(points)
        points.append(Vector2(0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
