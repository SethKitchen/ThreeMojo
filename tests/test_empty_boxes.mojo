# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Set semantics for finite and sentinel empty bounding boxes."""

from math.bounds import Box3
from math.box_extent import _shrink_exceeds_extent
from math.matrix2 import Box2
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_false, assert_true


def test_empty_box_containment_is_independent_of_corner_representation() raises:
    var full2 = Box2(Vector2(-1, -1), Vector2(1, 1))
    var full3 = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    var empty2 = Box2(Vector2(100, 100), Vector2(99, 101))
    var empty3 = Box3(Vector3(100, 100, 100), Vector3(99, 101, 101))
    assert_true(empty2.is_empty() and empty3.is_empty())
    for box in [full2, empty2, Box2.empty()]:
        assert_true(box.contains_box(empty2))
        assert_true(box.contains_box(Box2.empty()))
    for box in [full3, empty3, Box3.empty()]:
        assert_true(box.contains_box(empty3))
        assert_true(box.contains_box(Box3.empty()))
    assert_false(empty2.contains_box(full2))
    assert_false(empty3.contains_box(full3))
    assert_false(full2.contains_box(Box2(Vector2(0, 0), Vector2(2, 2))))
    assert_true(full2.contains_box(full2))
    assert_true(full3.contains_box(full3))


def test_empty_boxes_never_intersect_a_box() raises:
    var full2 = Box2(Vector2(-10, -10), Vector2(10, 10))
    var full3 = Box3(Vector3(-10, -10, -10), Vector3(10, 10, 10))
    var empty2 = Box2(Vector2(1, -1), Vector2(-1, 1))
    var empty3 = Box3(Vector3(1, -1, -1), Vector3(-1, 1, 1))
    for box in [full2, empty2, Box2.empty()]:
        assert_false(box.intersects_box(empty2))
        assert_false(empty2.intersects_box(box))
    for box in [full3, empty3, Box3.empty()]:
        assert_false(box.intersects_box(empty3))
        assert_false(empty3.intersects_box(box))
    assert_true(full2.intersects_box(Box2(Vector2(10, 10), Vector2(20, 20))))
    assert_true(
        full3.intersects_box(Box3(Vector3(10, 10, 10), Vector3(20, 20, 20)))
    )


def test_expansion_and_large_translation_do_not_revive_empty_boxes() raises:
    var empty2 = Box2(Vector2(1, -1), Vector2(-1, 1))
    var empty3 = Box3(Vector3(1, -1, -1), Vector3(-1, 1, 1))
    for initial in [empty2, Box2.empty()]:
        var box = initial
        box.expand_by_vector(Vector2(100, 100))
        assert_true(box.is_empty())
        box.expand_by_scalar(100)
        assert_true(box.is_empty())
        box.translate(Vector2(1e30, 1e30))
        assert_true(box.is_empty())
    for initial in [empty3, Box3.empty()]:
        var box = initial
        box.expand_by_vector(Vector3(100, 100, 100))
        assert_true(box.is_empty())
        box.expand_by_scalar(100)
        assert_true(box.is_empty())
        box.translate(Vector3(1e30, 1e30, 1e30))
        assert_true(box.is_empty())
    var full2 = Box2(Vector2(0, 0), Vector2(1, 1))
    full2.expand_by_scalar(1)
    full2.translate(Vector2(2, 2))
    assert_true(full2 == Box2(Vector2(1, 1), Vector2(4, 4)))
    var full3 = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
    full3.expand_by_vector(Vector3(1, 2, 3))
    full3.translate(Vector3(2, 2, 2))
    assert_true(full3 == Box3(Vector3(1, 0, -1), Vector3(4, 5, 6)))


def test_negative_sizes_remain_empty_when_rounding_erases_their_extent() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    for center in [Float32(0), Float32(1e30)]:
        for negative in [Float32(-1), -tiny]:
            assert_true(
                Box2.from_center_and_size(
                    Vector2(center, center), Vector2(negative, 1)
                ).is_empty()
            )
            assert_true(
                Box2.from_center_and_size(
                    Vector2(center, center), Vector2(1, negative)
                ).is_empty()
            )
            assert_true(
                Box3.from_center_and_size(
                    Vector3(center, center, center), Vector3(negative, 1, 1)
                ).is_empty()
            )
            assert_true(
                Box3.from_center_and_size(
                    Vector3(center, center, center), Vector3(1, negative, 1)
                ).is_empty()
            )
            assert_true(
                Box3.from_center_and_size(
                    Vector3(center, center, center), Vector3(1, 1, negative)
                ).is_empty()
            )
    assert_false(
        Box2.from_center_and_size(Vector2(0, 0), Vector2(0, 0)).is_empty()
    )
    assert_false(
        Box3.from_center_and_size(Vector3(0, 0, 0), Vector3(0, 0, 0)).is_empty()
    )
    # Keep ordinary negative-size corner arithmetic as before.
    assert_true(
        Box2.from_center_and_size(Vector2(0, 0), Vector2(-2, 2))
        == Box2(Vector2(1, -1), Vector2(-1, 1))
    )


def test_every_finite_empty_axis_obeys_set_operations() raises:
    var full2 = Box2(Vector2(-2, -2), Vector2(2, 2))
    var full3 = Box3(Vector3(-2, -2, -2), Vector3(2, 2, 2))
    for axis in range(2):
        var high = Vector2(51, 51)
        high.set_component(axis, 49)
        var empty = Box2(Vector2(50, 50), high)
        assert_true(full2.contains_box(empty))
        assert_false(empty.contains_box(full2))
        assert_false(full2.intersects_box(empty))
        assert_false(empty.intersects_box(full2))
        var joined = empty
        joined.union(full2)
        assert_true(joined == full2)
        joined.union(empty)
        assert_true(joined == full2)
        joined.intersect(empty)
        assert_true(joined.is_empty())
        joined = empty
        joined.intersect(full2)
        assert_true(joined.is_empty())
        empty.union(Box2.empty())
        empty.expand_by_scalar(100)
        empty.translate(Vector2(1e30, 1e30))
        assert_true(empty.is_empty())
    for axis in range(3):
        var high = Vector3(51, 51, 51)
        high.set_component(axis, 49)
        var empty = Box3(Vector3(50, 50, 50), high)
        assert_true(full3.contains_box(empty))
        assert_false(empty.contains_box(full3))
        assert_false(full3.intersects_box(empty))
        assert_false(empty.intersects_box(full3))
        var joined = empty
        joined.union(full3)
        assert_true(joined == full3)
        joined.union(empty)
        assert_true(joined == full3)
        joined.intersect(empty)
        assert_true(joined.is_empty())
        joined = empty
        joined.intersect(full3)
        assert_true(joined.is_empty())
        empty.union(Box3.empty())
        empty.expand_by_scalar(100)
        empty.translate(Vector3(1e30, 1e30, 1e30))
        assert_true(empty.is_empty())


def test_shrinking_then_expanding_does_not_revive_a_box() raises:
    for axis in range(2):
        var amount = Vector2(0, 0)
        amount.set_component(axis, -3)
        var box = Box2(Vector2(-2, -2), Vector2(2, 2))
        box.expand_by_vector(amount)
        assert_true(box.is_empty())
        box.expand_by_scalar(100)
        assert_true(box.is_empty())
    for axis in range(3):
        var amount = Vector3(0, 0, 0)
        amount.set_component(axis, -3)
        var box = Box3(Vector3(-2, -2, -2), Vector3(2, 2, 2))
        box.expand_by_vector(amount)
        assert_true(box.is_empty())
        box.expand_by_scalar(100)
        assert_true(box.is_empty())


def test_zero_width_and_touching_faces_remain_nonempty() raises:
    var face2 = Box2(Vector2(1, -1), Vector2(1, 1))
    var face3 = Box3(Vector3(1, -1, -1), Vector3(1, 1, 1))
    assert_false(face2.is_empty())
    assert_false(face3.is_empty())
    assert_true(face2.contains_point(Vector2(1, 0)))
    assert_true(face3.contains_point(Vector3(1, 0, 0)))
    assert_true(face2.intersects_box(face2))
    assert_true(face3.intersects_box(face3))
    var point2 = Box2(Vector2(0, 0), Vector2(0, 0))
    var point3 = Box3(Vector3(0, 0, 0), Vector3(0, 0, 0))
    point2.expand_by_scalar(1)
    point3.expand_by_scalar(1)
    assert_true(point2 == Box2(Vector2(-1, -1), Vector2(1, 1)))
    assert_true(point3 == Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1)))


def test_rounding_does_not_hide_over_shrinking() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    for center in [Float32(0), Float32(1e30)]:
        for amount in [Float32(-1), -tiny]:
            var box2 = Box2(Vector2(center, center), Vector2(center, center))
            var box3 = Box3(
                Vector3(center, center, center), Vector3(center, center, center)
            )
            box2.expand_by_scalar(amount)
            box3.expand_by_scalar(amount)
            assert_true(box2.is_empty())
            assert_true(box3.is_empty())
    # Exact span is one smallest subnormal less than the contraction.
    var box2 = Box2(Vector2(tiny, 0), Vector2(2, 2))
    var box3 = Box3(Vector3(tiny, 0, 0), Vector3(2, 2, 2))
    box2.expand_by_scalar(-1)
    box3.expand_by_scalar(-1)
    assert_true(box2.is_empty())
    assert_true(box3.is_empty())


def test_shrink_extent_comparison_keeps_tiny_endpoint_information() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    assert_true(_shrink_exceeds_extent(tiny, 2, -1))
    assert_false(_shrink_exceeds_extent(-tiny, 2, -1))
    assert_false(_shrink_exceeds_extent(0, 2, -1))
    assert_false(_shrink_exceeds_extent(0, 2, -0.5))
    assert_false(_shrink_exceeds_extent(0, 2, 1))
    assert_true(_shrink_exceeds_extent(0, 2, -2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
