# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Real producers reach the R-tree frontier, cap and speed-number loops."""
from extensions.carla.rtree import (
    SegmentCloudRtree,
    SegmentElement,
    SegmentFilter,
)
from extensions.carla.map_search import _MapQueryWork, MapQueryBudget
from extensions.carla.speed_limits import read_speed_number
from math.vector3 import Vector3
from objects.line_segments2 import cap_steps
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


@fieldwise_init
struct _AcceptEverySegment(ImplicitlyCopyable, SegmentFilter):
    def accepts(self, element: SegmentElement) -> Bool:
        return True


def test_empty_and_split_tree_frontiers_use_real_producers() raises:
    for count in [0, 1, 17, 257]:
        var tree = SegmentCloudRtree()
        for i in range(count):
            tree.insert_element(
                Vector3(Float32(i), 0, 0), Vector3(Float32(i), 1, 0), i, i
            )
        var point = Vector3(0, 0, 0)
        var work = _MapQueryWork(MapQueryBudget())
        var frontier = tree._nearest_begin(point, work)
        assert_equal(len(frontier.items), Int(count > 0))
        var found = 0
        while True:
            var next = tree._nearest_next(
                point, _AcceptEverySegment(), frontier, work
            )
            if not next:
                break
            assert_equal(next.value().start_value, found)
            found += 1
        assert_equal(found, count)
        assert_false(
            Bool(
                tree._nearest_next(point, _AcceptEverySegment(), frontier, work)
            )
        )
        if count > 0:
            for node in tree._tree.nodes:
                assert_true(len(node.children) > 0)
                assert_true(len(node.children) <= 16)


def test_cap_count_all_special_classes() raises:
    for radius in [
        Float32(-1),
        Float32(0),
        Float32(1),
        Float32(1e30),
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
        bitcast[DType.float32](UInt32(0x7F800001)),
        bitcast[DType.float32](UInt32(0xFF800001)),
    ]:
        var count = cap_steps(radius)
        assert_true(count >= 2 and count <= 64)


def test_owned_nonempty_zero_mantissa_byte_view() raises:
    assert_equal(read_speed_number("0.000"), Float64(0))
    assert_equal(read_speed_number("-0E-1000"), Float64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
