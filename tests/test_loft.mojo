# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.loft` and `objects.wireframe_geometry2`.

The expected numbers are what three.js r186's `LoftGeometry` gives for the
same sections, rounded to six places.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.box import cube
from geometries.edges import wireframe_geometry
from geometries.loft import loft
from math.vector3 import Vector3
from objects.wireframe_geometry2 import wireframe_geometry2
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def loft_closed_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [
        Float32(1),
        0,
        1,
        1,
        0,
        -1,
        -1,
        0,
        -1,
        -1,
        0,
        1,
        1,
        0,
        1,
        0.5,
        1,
        0.5,
        0.5,
        1,
        -0.5,
        -0.5,
        1,
        -0.5,
        -0.5,
        1,
        0.5,
        0.5,
        1,
        0.5,
        0.5,
        3,
        0.5,
        0.5,
        3,
        -0.5,
        -0.5,
        3,
        -0.5,
        -0.5,
        3,
        0.5,
        0.5,
        3,
        0.5,
        -1,
        0,
        1,
        -1,
        0,
        -1,
        1,
        0,
        -1,
        1,
        0,
        1,
        0.5,
        3,
        0.5,
        0.5,
        3,
        -0.5,
        -0.5,
        3,
        -0.5,
        -0.5,
        3,
        0.5,
    ]


def loft_closed_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0.57735),
        0.57735,
        0.57735,
        0.683763,
        0.569803,
        -0.455842,
        -0.455842,
        0.569803,
        -0.683763,
        -0.683763,
        0.569803,
        0.455842,
        0.57735,
        0.57735,
        0.57735,
        0.667806,
        0.269717,
        0.69375,
        0.680414,
        0.272166,
        -0.680414,
        -0.680414,
        0.272166,
        -0.680414,
        -0.680414,
        0.272166,
        0.680414,
        0.667806,
        0.269717,
        0.69375,
        0.707107,
        0,
        0.707107,
        0.447214,
        0,
        -0.894427,
        -0.894427,
        0,
        -0.447214,
        -0.447214,
        0,
        0.894427,
        0.707107,
        0,
        0.707107,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
    ]


def loft_closed_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [
        Float32(0),
        0,
        0,
        0.25,
        0,
        0.5,
        0,
        0.75,
        0,
        1,
        0.379796,
        0,
        0.379796,
        0.25,
        0.379796,
        0.5,
        0.379796,
        0.75,
        0.379796,
        1,
        1,
        0,
        1,
        0.25,
        1,
        0.5,
        1,
        0.75,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
    ]


def loft_closed_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [
        0,
        1,
        5,
        1,
        6,
        5,
        1,
        2,
        6,
        2,
        7,
        6,
        2,
        3,
        7,
        3,
        8,
        7,
        3,
        4,
        8,
        4,
        9,
        8,
        5,
        6,
        10,
        6,
        11,
        10,
        6,
        7,
        11,
        7,
        12,
        11,
        7,
        8,
        12,
        8,
        13,
        12,
        8,
        9,
        13,
        9,
        14,
        13,
        17,
        18,
        15,
        15,
        16,
        17,
        21,
        22,
        19,
        19,
        20,
        21,
    ]


def loft_x_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [
        Float32(0),
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        2,
        1,
        0,
        2,
        1,
        1,
        2,
        0,
        1,
        2,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        2,
        1,
        0,
        2,
        1,
        1,
        2,
        0,
        1,
    ]


def loft_x_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0),
        -0.707107,
        -0.707107,
        0,
        0.447214,
        -0.894427,
        0,
        0.894427,
        0.447214,
        0,
        -0.447214,
        0.894427,
        0,
        -0.707107,
        -0.707107,
        0,
        -0.707107,
        -0.707107,
        0,
        0.894427,
        -0.447214,
        0,
        0.447214,
        0.894427,
        0,
        -0.894427,
        0.447214,
        0,
        -0.707107,
        -0.707107,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
    ]


def loft_x_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [
        Float32(0),
        0,
        0,
        0.25,
        0,
        0.5,
        0,
        0.75,
        0,
        1,
        1,
        0,
        1,
        0.25,
        1,
        0.5,
        1,
        0.75,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
    ]


def loft_x_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [
        0,
        1,
        5,
        1,
        6,
        5,
        1,
        2,
        6,
        2,
        7,
        6,
        2,
        3,
        7,
        3,
        8,
        7,
        3,
        4,
        8,
        4,
        9,
        8,
        12,
        13,
        10,
        10,
        11,
        12,
        16,
        17,
        14,
        14,
        15,
        16,
    ]


def loft_open_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [Float32(0), 0, 0, 1, 0, 0, 3, 0, 0, 0, 0, 2, 1, 1, 2, 3, 0, 2]


def loft_open_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0),
        -1,
        0,
        0.227921,
        -0.911685,
        0.341882,
        -0.235702,
        -0.942809,
        0.235702,
        0.436436,
        -0.872872,
        0.218218,
        0,
        -0.957826,
        0.287348,
        -0.447214,
        -0.894427,
        0,
    ]


def loft_open_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [Float32(0), 0, 0, 0.333333, 0, 1, 1, 0, 1, 0.387426, 1, 1]


def loft_open_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [0, 1, 3, 1, 4, 3, 1, 2, 4, 2, 5, 4]


def square(y: Float32, half: Float32) -> List[Vector3]:
    """Return a square section across the y axis, three.js's test's."""
    return [
        Vector3(half, y, half),
        Vector3(half, y, -half),
        Vector3(-half, y, -half),
        Vector3(-half, y, half),
    ]


def ring(x: Float32) -> List[Vector3]:
    """Return a square section across the x axis."""
    return [
        Vector3(x, 0, 0),
        Vector3(x, 1, 0),
        Vector3(x, 1, 1),
        Vector3(x, 0, 1),
    ]


def assert_floats(
    geometry: BufferGeometry, name: String, expected: List[Float32]
) raises:
    """Assert that an attribute holds three.js's numbers, to six places."""
    ref got = geometry.attribute_view(name)
    assert_equal(len(got.data), len(expected), name)
    for index in range(len(expected)):
        assert_almost_equal(got.data[index], expected[index], atol=2e-5)


def assert_matches(
    geometry: BufferGeometry,
    position: List[Float32],
    normal: List[Float32],
    uv: List[Float32],
    index: List[Int],
) raises:
    """Assert that a geometry is three.js's, attribute by attribute."""
    assert_floats(geometry, POSITION, position)
    assert_floats(geometry, NORMAL, normal)
    assert_floats(geometry, UV, uv)
    assert_equal(len(geometry.index), len(index))
    for at in range(len(index)):
        assert_equal(geometry.index[at], index[at])


def test_a_closed_tapering_loft_with_both_caps_is_threes() raises:
    var geometry = loft(
        [square(0, 1), square(1, 0.5), square(3, 0.5)],
        cap_start=True,
        cap_end=True,
    )
    assert_matches(
        geometry,
        loft_closed_position(),
        loft_closed_normal(),
        loft_closed_uv(),
        loft_closed_index(),
    )


def test_a_loft_along_x_lays_its_caps_on_another_tangent() raises:
    # The caps face along x, so the tangent three.js starts from is y.
    var geometry = loft([ring(0), ring(2)], cap_start=True, cap_end=True)
    assert_matches(
        geometry,
        loft_x_position(),
        loft_x_normal(),
        loft_x_uv(),
        loft_x_index(),
    )


def test_an_open_loft_is_a_strip() raises:
    var geometry = loft(
        [
            [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0)],
            [Vector3(0, 0, 2), Vector3(1, 1, 2), Vector3(3, 0, 2)],
        ],
        closed=False,
    )
    assert_matches(
        geometry,
        loft_open_position(),
        loft_open_normal(),
        loft_open_uv(),
        loft_open_index(),
    )


def test_sections_of_no_length_fall_back_to_even_texture_coordinates() raises:
    # Every section is the same point twice: no distance along the loft
    # and none around a section, so u and v step evenly, as three.js's
    # `i / ( rows - 1 )` and `j / ( pointsPerRow - 1 )`.
    var point = Vector3(1, 2, 3)
    var geometry = loft(
        [[point, point], [point, point], [point, point]], closed=False
    )
    ref uv = geometry.attribute_view(UV)
    assert_almost_equal(uv.data[0], 0)
    assert_almost_equal(uv.data[1], 0)
    assert_almost_equal(uv.data[3], 1)
    assert_almost_equal(uv.data[4], 0.5)
    assert_almost_equal(uv.data[10], 1)


def test_a_cap_of_two_points_has_no_triangle() raises:
    # Two points enclose nothing: the cap adds its vertices and no face.
    var geometry = loft(
        [
            [Vector3(0, 0, 0), Vector3(1, 0, 0)],
            [Vector3(0, 1, 0), Vector3(1, 1, 0)],
        ],
        closed=False,
        cap_start=True,
    )
    assert_equal(geometry.attribute_view(POSITION).count(), 6)
    assert_equal(len(geometry.index), 6)


def test_a_loft_refuses_sections_it_cannot_join() raises:
    with assert_raises(contains="two sections"):
        _ = loft([square(0, 1)])
    with assert_raises(contains="two points"):
        _ = loft([[Vector3(0, 0, 0)], [Vector3(0, 1, 0)]])
    with assert_raises(contains="same number"):
        var three: List[Vector3] = [
            Vector3(1, 1, 1),
            Vector3(1, 1, 0),
            Vector3(0, 1, 0),
        ]
        _ = loft([square(0, 1), three^])
    var bad = square(1, 1)
    bad[2] = Vector3(nan[DType.float32](), 1, 0)
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])
    bad[2] = Vector3(0, inf[DType.float32](), 0)
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])
    bad[2] = Vector3(0, 1, -inf[DType.float32]())
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])


def test_a_wireframe2_holds_every_edge_of_a_box_once() raises:
    # three.js's `WireframeGeometry2` of a unit `BoxGeometry` holds 18
    # segments: twelve edges and a diagonal across each face.
    var box = cube(Length(1.0, METER))
    var wide = wireframe_geometry2(box)
    ref points = wide.attribute_view(POSITION)
    assert_equal(points.count(), 36)
    var plain = wireframe_geometry(box)
    ref expected = plain.attribute_view(POSITION)
    for index in range(len(expected.data)):
        assert_almost_equal(points.data[index], expected.data[index])


def test_a_wireframe2_of_nothing_is_empty() raises:
    var empty = BufferGeometry()
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    var wide = wireframe_geometry2(empty)
    assert_equal(wide.attribute_view(POSITION).count(), 0)
    with assert_raises():
        _ = wireframe_geometry2(BufferGeometry())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
