# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.teapot` and `geometries.box_line`.

The expected numbers are what three.js 0.180's `TeapotGeometry` and
`BoxLineGeometry` give under node."""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.box_line import box_line
from geometries.teapot import teapot
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length, METER


def meters(value: Float32) -> Length:
    """Return `value` meters."""
    return Length(value, METER)


def assert_vertex(
    geometry: BufferGeometry,
    vertex: Int,
    position: List[Float64],
    normal: List[Float64],
    uv: List[Float64],
) raises:
    """Check one vertex's position, normal and texture coordinate."""
    ref p = geometry.attribute_view(String(POSITION))
    ref n = geometry.attribute_view(String(NORMAL))
    ref u = geometry.attribute_view(String(UV))
    for axis in range(3):
        assert_almost_equal(
            Float64(p.component(vertex, axis)), position[axis], atol=1e-4
        )
        assert_almost_equal(
            Float64(n.component(vertex, axis)), normal[axis], atol=1e-6
        )
    for axis in range(2):
        assert_almost_equal(
            Float64(u.component(vertex, axis)), uv[axis], atol=1e-7
        )


def index_sum(geometry: BufferGeometry) -> Int:
    """Return the sum of every index entry."""
    var total = 0
    for entry in geometry.index:
        total += entry
    return total


def test_the_default_teapot_matches_three() raises:
    var pot = teapot()
    assert_equal(pot.vertex_count(), 3872)
    assert_equal(len(pot.index), 18960)
    assert_equal(index_sum(pot), 36418960)
    assert_equal(pot.index[0], 0)
    assert_equal(pot.index[1], 1)
    assert_equal(pot.index[2], 12)
    assert_equal(pot.index[18959], 3870)
    assert_vertex(
        pot,
        0,
        [44.44444274902344, 26.190475463867188, 0],
        [-0.9028605222702026, -0.4299335777759552, 0],
        [1, 1],
    )
    assert_vertex(
        pot,
        50,
        [26.211669921875, 29.190475463867188, 35.716224670410156],
        [-0.34927627444267273, 0.8051414489746094, -0.47932595014572144],
        [0.4000000059604645, 0.6000000238418579],
    )
    # The top of the lid, where the normal points straight up.
    assert_vertex(
        pot,
        1936,
        [53.96825408935547, -4.761904716491699, 0],
        [0, 1, 0],
        [1, 1],
    )
    assert_vertex(
        pot,
        3871,
        [47.619049072265625, -45.238094329833984, 0],
        [1, 0, 0],
        [0, 0],
    )


def test_a_tall_teapot_with_an_unfitted_lid_matches_three() raises:
    var pot = teapot(meters(2), 3, True, True, True, False, False)
    assert_equal(pot.vertex_count(), 512)
    assert_equal(len(pot.index), 1656)
    assert_equal(index_sum(pot), 411912)
    assert_vertex(
        pot,
        7,
        [0, 1.158730149269104, 1.352145791053772],
        [0, 0.38341397047042847, -0.9235765933990479],
        [0, 0.6666666865348816],
    )
    assert_vertex(
        pot,
        121,
        [0.9559518098831177, -0.25749558210372925, -1.6276264190673828],
        [0.49020230770111084, 0.21302248537540436, -0.8451763987541199],
        [0.6666666865348816, 0.3333333432674408],
    )


def test_a_teapot_can_leave_out_parts() raises:
    var no_lid = teapot(meters(1), 2, True, False, True)
    assert_equal(no_lid.vertex_count(), 216)
    assert_equal(len(no_lid.index), 552)
    assert_equal(index_sum(no_lid), 57224)
    # The middle of the bottom, where the normal points down.
    assert_vertex(
        no_lid,
        108,
        [-1.0158730745315552, 0.2857142984867096, 0],
        [0, -1, 0],
        [1, 1],
    )
    var lid_only = teapot(meters(1), 2, False, True, False)
    assert_equal(lid_only.vertex_count(), 72)
    assert_equal(len(lid_only.index), 168)
    assert_equal(index_sum(lid_only), 6440)
    assert_equal(lid_only.index[1], 4)
    var nothing = teapot(meters(1), 2, False, False, False)
    assert_equal(nothing.vertex_count(), 0)
    assert_equal(len(nothing.index), 0)


def test_a_teapot_needs_a_size_and_two_segments() raises:
    with assert_raises():
        _ = teapot(meters(0))
    with assert_raises():
        _ = teapot(meters(-1))
    with assert_raises():
        _ = teapot(Length(Float32.MAX * 2, METER))
    with assert_raises():
        _ = teapot(meters(1), 1)


def test_a_box_of_lines_matches_three() raises:
    var box = box_line(meters(2), meters(3), meters(4), 2, 3, 1)
    ref p = box.attribute_view(String(POSITION))
    assert_equal(p.count(), 72)
    assert_equal(box.is_indexed(), False)
    var expected: List[List[Float32]] = [
        [-1, -1.5, -2],
        [-1, 1.5, -2],
    ]
    for vertex in range(2):
        for axis in range(3):
            assert_equal(p.component(vertex, axis), expected[vertex][axis])
    assert_equal(p.component(50, 0), 1)
    assert_equal(p.component(50, 1), 1.5)
    assert_equal(p.component(36, 1), -0.5)
    assert_equal(p.component(71, 2), 2)
    var thirds = box_line(width_segments=3)
    ref q = thirds.attribute_view(String(POSITION))
    assert_equal(q.component(8, 0), -0.1666666716337204)
    assert_equal(q.count(), 64)


def test_a_box_of_lines_needs_extents_and_segments() raises:
    with assert_raises():
        _ = box_line(meters(0))
    with assert_raises():
        _ = box_line(height=meters(0))
    with assert_raises():
        _ = box_line(depth=meters(-1))
    with assert_raises():
        _ = box_line(width_segments=0)
    with assert_raises():
        _ = box_line(height_segments=0)
    with assert_raises():
        _ = box_line(depth_segments=0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
