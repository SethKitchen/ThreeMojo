# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Stable draw sorting across the insertion and merge paths."""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from render.rasterizer import DRAW_TRIANGLES
from renderers.renderer import (
    RenderItem,
    RenderSort,
    _Source,
    _Span,
    _sort_by,
    _sort_with,
)
from std.testing import TestSuite, assert_equal, assert_true


def test_draw_indices_keys_and_orders_stay_together() raises:
    for count in [0, 1, 2, 32, 33, 65, 1024]:
        var items = List[Int]()
        var keys = List[Float32]()
        var orders = List[Int]()
        for index in range(count):
            items.append(index)
            keys.append(Float32((index * 37) % 11 - 5))
            orders.append(index % 5 - 2)
        _sort_by(items, keys, orders)
        for index in range(count):
            assert_equal(keys[index], Float32((items[index] * 37) % 11 - 5))
            assert_equal(orders[index], items[index] % 5 - 2)
            if index > 0:
                assert_true(orders[index - 1] <= orders[index])
                if orders[index - 1] == orders[index]:
                    assert_true(keys[index - 1] <= keys[index])
                    if keys[index - 1] == keys[index]:
                        assert_true(items[index - 1] < items[index])
        # A second pass must preserve the complete already-sorted list.
        var original = items.copy()
        _sort_by(items, keys, orders)
        for index in range(count):
            assert_equal(items[index], original[index])


def _order_only(a: RenderItem, b: RenderItem) -> Bool:
    return a.order < b.order


def _depth_descending(a: RenderItem, b: RenderItem) -> Bool:
    return a.z > b.z


def test_custom_draw_sort_keeps_sources_and_matches_stable_reference() raises:
    for count in [0, 1, 32, 33, 65, 257]:
        var original = List[_Span]()
        for index in range(count):
            original.append(
                _Span(
                    DRAW_TRIANGLES,
                    index * 3,
                    3,
                    Float32((index * 37) % 11 - 5),
                    True,
                    index % 5 - 2,
                    _Source(
                        NodeId(index), GeometryId(index), MaterialId(index)
                    ),
                )
            )
        for choice in range(2):
            var before: RenderSort = _order_only
            if choice == 1:
                before = _depth_descending
            var expected = original.copy()
            # Independent, simple reference for the public comparator contract.
            for position in range(1, len(expected)):
                var held = expected[position]
                var slot = position
                while slot > 0 and before(
                    held.item(), expected[slot - 1].item()
                ):
                    expected[slot] = expected[slot - 1]
                    slot -= 1
                expected[slot] = held
            var got = original.copy()
            _sort_with(got, before)
            for index in range(count):
                assert_equal(got[index].first, expected[index].first)
                assert_equal(
                    got[index].source.node, expected[index].source.node
                )
                assert_equal(got[index].depth, expected[index].depth)
                assert_equal(got[index].order, expected[index].order)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
