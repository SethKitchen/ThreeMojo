# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Dimension-safe R-tree packing, checked against independent scans."""

from extensions.carla.rtree import (
    PointCloudRtree,
    PointElement,
    PointFilter,
    SegmentCloudRtree,
    SegmentElement,
    SegmentFilter,
    _PackingCost,
    _extent,
    _packing_cost,
)
from math.bounds import Box3
from math.vector3 import Vector3
from std.math import isinf, isnan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


@fieldwise_init
struct _EvenPoints(ImplicitlyCopyable, PointFilter):
    def accepts(self, element: PointElement) -> Bool:
        return element.value % 2 == 0


@fieldwise_init
struct _EvenSegments(ImplicitlyCopyable, SegmentFilter):
    def accepts(self, element: SegmentElement) -> Bool:
        return element.start_value % 2 == 0


def test_extent_compares_each_dimension_separately() raises:
    var origin = Vector3(0, 0, 0)
    var solid = _extent(Box3(origin, Vector3(2, 3, 4)))
    assert_equal(solid[0], 24.0)
    assert_equal(solid[1], 26.0)
    assert_equal(solid[2], 9.0)
    var plane = _extent(Box3(origin, Vector3(2, 3, 0)))
    assert_equal(plane[0], 0.0)
    assert_equal(plane[1], 6.0)
    assert_equal(plane[2], 5.0)
    var cost = _packing_cost(
        Box3(origin, Vector3(2, 3, 0)), Box3(origin, Vector3(2, 3, 4))
    )
    assert_equal(cost.volume_growth, 24.0)
    assert_equal(cost.volume, 0.0)
    assert_equal(cost.area_growth, 20.0)
    assert_equal(cost.area, 6.0)
    assert_equal(cost.length_growth, 4.0)
    assert_equal(cost.length, 5.0)
    var zero = _PackingCost(0, 0, 0, 0, 0, 0)
    assert_equal(zero.compare(zero), 0)
    var costs: List[_PackingCost] = [
        _PackingCost(1, 0, 0, 0, 0, 0),
        _PackingCost(0, 1, 0, 0, 0, 0),
        _PackingCost(0, 0, 1, 0, 0, 0),
        _PackingCost(0, 0, 0, 1, 0, 0),
        _PackingCost(0, 0, 0, 0, 1, 0),
        _PackingCost(0, 0, 0, 0, 0, 1),
    ]
    for i in range(len(costs)):
        assert_equal(costs[i].compare(zero), 1)
        assert_equal(zero.compare(costs[i]), -1)
        for j in range(i + 1, len(costs)):
            assert_equal(costs[i].compare(costs[j]), 1)
            assert_equal(costs[j].compare(costs[i]), -1)
    # The original volume-size tie rule precedes every lower-dimensional
    # term, however large the lower-dimensional values are.
    assert_equal(
        _PackingCost(0, 0, 1e9, 1e9, 1e9, 1e9).compare(
            _PackingCost(0, 1, 0, 0, 0, 0)
        ),
        -1,
    )


def test_extent_preserves_finite_limits_and_subnormals() raises:
    var limit = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var wide = Float64(limit) * 2
    var large = _extent(
        Box3(Vector3(-limit, -limit, -limit), Vector3(limit, limit, limit))
    )
    assert_false(isinf(large[0]))
    assert_false(isnan(large[0]))
    assert_equal(large[0], wide * wide * wide)
    assert_equal(large[1], 3 * wide * wide)
    assert_equal(large[2], 3 * wide)
    var tiny = bitcast[DType.float32](UInt32(1))
    var span = Float64(tiny) * 2
    var small = _extent(
        Box3(Vector3(-tiny, -tiny, -tiny), Vector3(tiny, tiny, tiny))
    )
    assert_true(small[0] > 0)
    assert_equal(small[0], span * span * span)
    assert_equal(small[1], 3 * span * span)
    assert_equal(small[2], 3 * span)
    var tree = PointCloudRtree()
    for i in range(17):
        var x = -limit if i % 2 == 0 else limit
        tree.insert_element(Vector3(x, Float32(i), 0), i)
    var got = tree.get_nearest_neighbours(Vector3(limit, 1, 0), 17)
    assert_equal(got[0].value, 1)
    assert_equal(len(got), 17)


def test_seventeen_ordered_entries_do_not_overlap() raises:
    # With volume alone, all costs are zero. The old two leaves span
    # [0, 15] and [2, 16]. They overlap despite this simple ordered input.
    for dimensions in range(1, 4):
        var tree = PointCloudRtree()
        for i in range(17):
            var y = Float32(0)
            var z = Float32(0)
            if dimensions >= 2:
                y = Float32(i)
            if dimensions == 3:
                z = Float32(i)
            tree.insert_element(Vector3(Float32(i), y, z), i)
        var root = tree._tree.root
        assert_equal(len(tree._tree.nodes[root].children), 2)
        var a = tree._tree.nodes[tree._tree.nodes[root].children[0]].box
        var b = tree._tree.nodes[tree._tree.nodes[root].children[1]].box
        assert_true(a.max.x < b.min.x or b.max.x < a.min.x)
        for i in range(17):
            var point = tree._tree.starts[i]
            var got = tree.get_nearest_neighbours(point)
            assert_equal(got[0].value, i)


def _coordinate(i: Int, dimensions: Int, axis: Int) -> Vector3:
    # Permuted insertion order, including repeated points, in all three
    # coordinate planes and lines. Mode four mixes dimensions in one tree.
    var n = (i * 71) % 257
    var x = Float32(n % 17)
    var y = Float32((n // 17) % 17)
    var z = Float32((n * 11) % 19)
    var active = dimensions
    if dimensions == 4:
        active = i % 4
    if active < 3:
        z = 0
    if active < 2:
        y = 0
    if active < 1:
        x = 0
    if axis == 0:
        return Vector3(x, y, z)
    if axis == 1:
        return Vector3(z, x, y)
    return Vector3(y, z, x)


def _ordered(keys: List[Float64], even: Bool) -> List[Int]:
    # Stable insertion sort: no tree boxes, heap, or production distance code.
    var order = List[Int]()
    for i in range(len(keys)):
        if even and i % 2 != 0:
            continue
        order.append(i)
        var at = len(order) - 1
        while at > 0 and keys[order[at]] < keys[order[at - 1]]:
            order.swap_elements(at, at - 1)
            at -= 1
    return order^


def _check_points(dimensions: Int) raises:
    for axis in range(3):
        var points = List[Vector3]()
        var tree = PointCloudRtree()
        for i in range(320):
            var point = _coordinate(i, dimensions, axis)
            points.append(point)
            tree.insert_element(point, i)
        for q in range(9):
            var query = _coordinate(q * 29, 3, axis) + Vector3(0.5, 0.5, 0.5)
            var keys = List[Float64]()
            for point in points:
                var dx = Float64(point.x) - Float64(query.x)
                var dy = Float64(point.y) - Float64(query.y)
                var dz = Float64(point.z) - Float64(query.z)
                keys.append(dx * dx + dy * dy + dz * dz)
            var order = _ordered(keys, False)
            var even = _ordered(keys, True)
            var got = tree.get_nearest_neighbours(query, 320)
            var filtered = tree.get_nearest_neighbours_with_filter(
                query, _EvenPoints(), 320
            )
            assert_equal(len(got), 320)
            assert_equal(len(filtered), 160)
            for i in range(320):
                assert_equal(got[i].value, order[i])
            for i in range(160):
                assert_equal(filtered[i].value, even[i])


def test_linear_points_match_an_independent_scan() raises:
    _check_points(1)


def test_planar_points_match_an_independent_scan() raises:
    _check_points(2)


def test_solid_points_match_an_independent_scan() raises:
    _check_points(3)


def test_mixed_points_match_an_independent_scan() raises:
    _check_points(4)


def test_segments_keep_distance_ties_payloads_and_intersection_order() raises:
    for dimensions in range(1, 5):
        var starts = List[Vector3]()
        var ends = List[Vector3]()
        var tree = SegmentCloudRtree()
        for i in range(320):
            var start = _coordinate(i, dimensions, 0)
            var end = start + Vector3(Float32(i % 4), 0, 0)
            starts.append(start)
            ends.append(end)
            # Values run backward: ties must use insertion, not payload.
            tree.insert_element(start, end, 1000 - i, 2000 - i)
        for q in range(9):
            var query = _coordinate(q * 29, 3, 0) + Vector3(0.5, 0.5, 0.5)
            var keys = List[Float64]()
            for i in range(320):
                # The segment is an x interval, so its closest x is a
                # clamped coordinate; no projection or tree helper is used.
                var x = min(max(query.x, starts[i].x), ends[i].x)
                var dx = Float64(x) - Float64(query.x)
                var dy = Float64(starts[i].y) - Float64(query.y)
                var dz = Float64(starts[i].z) - Float64(query.z)
                keys.append(dx * dx + dy * dy + dz * dz)
            var order = _ordered(keys, False)
            var even = _ordered(keys, True)
            var got = tree.get_nearest_neighbours(query, 320)
            var filtered = tree.get_nearest_neighbours_with_filter(
                query, _EvenSegments(), 320
            )
            assert_equal(len(got), 320)
            assert_equal(len(filtered), 160)
            for i in range(320):
                assert_equal(got[i].start_value, 1000 - order[i])
                assert_equal(got[i].end_value, 2000 - order[i])
            for i in range(160):
                assert_equal(filtered[i].start_value, 1000 - even[i])
        for q in range(5):
            var low = Float32(q * 3)
            var box = Box3(Vector3(low, -1, -1), Vector3(low + 2, 20, 20))
            var hits = tree.get_intersections(box)
            var expected = 0
            for i in range(320):
                # Every y and z is inside the slab by construction.
                if ends[i].x >= low and starts[i].x <= low + 2:
                    assert_equal(hits[expected].start_value, 1000 - i)
                    expected += 1
            assert_equal(len(hits), expected)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
