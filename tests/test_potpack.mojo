# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for mapbox's `potpack`: the places and the container it gives,
checked against the JavaScript's own answers."""

from math.potpack import PackedBox, potpack
from std.testing import TestSuite, assert_almost_equal, assert_equal


def box(w: Float64, h: Float64, index: Int) -> PackedBox:
    """Return a box to pack, not yet placed."""
    return PackedBox(w, h, 0, 0, index)


def test_no_boxes_pack_into_nothing() raises:
    var boxes = List[PackedBox]()
    var packing = potpack(boxes)
    assert_equal(packing.w, 0)
    assert_equal(packing.h, 0)
    assert_equal(packing.fill, 0)


def test_one_box_fills_its_container() raises:
    var boxes: List[PackedBox] = [box(1.5, 1.5, 0)]
    var packing = potpack(boxes)
    assert_equal(packing.w, 1.5)
    assert_equal(packing.h, 1.5)
    assert_equal(packing.fill, 1)
    assert_equal(boxes[0].x, 0)
    assert_equal(boxes[0].y, 0)


def test_the_tallest_go_first_and_equals_keep_their_order() raises:
    # The JavaScript's answer for these boxes: potpack([{w:2,h:1},
    # {w:1,h:3},{w:2,h:1},{w:3,h:2}]).
    var boxes: List[PackedBox] = [
        box(2, 1, 0),
        box(1, 3, 1),
        box(2, 1, 2),
        box(3, 2, 3),
    ]
    var packing = potpack(boxes)
    assert_equal(boxes[0].index, 1)
    assert_equal(boxes[1].index, 3)
    assert_equal(boxes[2].index, 0)
    assert_equal(boxes[3].index, 2)
    # The start is ceil(sqrt(13 / 0.95)) = 4 wide.
    assert_equal(boxes[0].x, 0)
    assert_equal(boxes[0].y, 0)
    assert_equal(boxes[1].x, 1)
    assert_equal(boxes[1].y, 0)
    # The first two-wide box fits under the three-wide one.
    assert_equal(boxes[2].x, 1)
    assert_equal(boxes[2].y, 2)
    assert_equal(boxes[3].x, 0)
    assert_equal(boxes[3].y, 3)
    assert_equal(packing.w, 4)
    assert_equal(packing.h, 4)
    assert_almost_equal(packing.fill, 13.0 / 16.0)


def test_a_box_as_tall_as_its_space_moves_it_along() raises:
    # Five squares three to a row: the second and the fifth are as tall
    # as the space the one before split off, and the third fills it.
    var boxes: List[PackedBox] = [
        box(1, 1, 0),
        box(1, 1, 1),
        box(1, 1, 2),
        box(1, 1, 3),
        box(1, 1, 4),
    ]
    var packing = potpack(boxes)
    assert_equal(packing.w, 3)
    assert_equal(packing.h, 2)
    assert_equal(boxes[2].x, 2)
    assert_equal(boxes[2].y, 0)
    assert_equal(boxes[3].x, 0)
    assert_equal(boxes[3].y, 1)
    assert_equal(boxes[4].x, 1)
    assert_equal(boxes[4].y, 1)


def test_a_box_as_wide_as_its_space_moves_it_down() raises:
    var boxes: List[PackedBox] = [box(3, 1, 0), box(1, 1, 1)]
    var packing = potpack(boxes)
    assert_equal(boxes[1].x, 0)
    assert_equal(boxes[1].y, 1)
    assert_equal(packing.w, 3)
    assert_equal(packing.h, 2)


def test_the_last_space_takes_the_place_of_one_filled() raises:
    # The three-wide box fills the space under the tall ones, and the
    # space beside the two-tall box takes its place: the last box lands
    # in it.
    var boxes: List[PackedBox] = [
        box(1, 3, 0),
        box(1, 2, 1),
        box(3, 1, 2),
        box(1, 1, 3),
    ]
    var packing = potpack(boxes)
    assert_equal(boxes[2].x, 1)
    assert_equal(boxes[2].y, 2)
    assert_equal(boxes[3].x, 2)
    assert_equal(boxes[3].y, 0)
    assert_equal(packing.w, 4)
    assert_equal(packing.h, 3)
    assert_almost_equal(packing.fill, 0.75)


def test_a_box_too_tall_for_a_space_goes_below() raises:
    # The two-tall box fits the space beside the three-tall one; the
    # last is as narrow but too tall for what that space has left, and
    # goes below.
    var boxes: List[PackedBox] = [box(2, 3, 0), box(2, 2, 1), box(2, 2, 2)]
    var packing = potpack(boxes)
    assert_equal(boxes[1].x, 2)
    assert_equal(boxes[1].y, 0)
    assert_equal(boxes[2].x, 0)
    assert_equal(boxes[2].y, 3)
    assert_equal(packing.w, 4)
    assert_equal(packing.h, 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
