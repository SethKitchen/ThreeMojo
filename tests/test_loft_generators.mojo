# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.loft`, three.js's `LoftGeometry`.

The expected numbers follow from three.js r186's
`examples/jsm/geometries/LoftGeometry.js` on small sections worked by
hand: a square prism, a ribbon and a tapered ring.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.loft import loft
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _square(y: Float32, half: Float32 = 1) -> List[Vector3]:
    """Return a square section at a height, counter-clockwise seen from
    above."""
    return [
        Vector3(half, y, half),
        Vector3(half, y, -half),
        Vector3(-half, y, -half),
        Vector3(-half, y, half),
    ]


def _check(
    geometry: BufferGeometry,
    name: String,
    index: Int,
    x: Float32,
    y: Float32,
    z: Float32,
) raises:
    """Assert one item of an attribute."""
    var v = geometry.attribute_view(name).vector3(index)
    assert_almost_equal(v.x, x, atol=1e-6)
    assert_almost_equal(v.y, y, atol=1e-6)
    assert_almost_equal(v.z, z, atol=1e-6)


def test_a_capped_prism() raises:
    """Two squares make a prism: five points a ring with the seam, then
    each cap's four, and the caps face away from the walls."""
    var sections: List[List[Vector3]] = [_square(0), _square(1)]
    var geometry = loft(sections, True, True, True)
    assert_equal(geometry.vertex_count(), 10 + 4 + 4)
    assert_equal(len(geometry.index), 24 + 6 + 6)
    assert_equal(geometry.index[0], 0)
    assert_equal(geometry.index[1], 1)
    assert_equal(geometry.index[2], 5)
    assert_equal(geometry.index[3], 1)
    assert_equal(geometry.index[4], 6)
    assert_equal(geometry.index[5], 5)
    # The seam's two copies share one normal.
    var first = geometry.attribute_view(String(NORMAL)).vector3(0)
    var last = geometry.attribute_view(String(NORMAL)).vector3(4)
    assert_almost_equal(first.x, last.x, atol=1e-6)
    assert_almost_equal(first.z, last.z, atol=1e-6)
    # u along the loft, v round the ring by distance: a side is a quarter.
    ref uv = geometry.attribute_view(String(UV))
    assert_equal(uv.component(0, 0), 0)
    assert_equal(uv.component(5, 0), 1)
    assert_almost_equal(uv.component(1, 1), 0.25, atol=1e-6)
    assert_almost_equal(uv.component(4, 1), 1.0, atol=1e-6)
    # The start cap looks down and the end cap up.
    _check(geometry, String(NORMAL), 10, 0, -1, 0)
    _check(geometry, String(NORMAL), 14, 0, 1, 0)


def test_an_open_ribbon() raises:
    """An open strip has no seam copy and no averaging."""
    var a: List[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0)]
    var b: List[Vector3] = [Vector3(0, 0, 1), Vector3(1, 0, 1)]
    var geometry = loft([a^, b^], False)
    assert_equal(geometry.vertex_count(), 4)
    assert_equal(len(geometry.index), 6)
    _check(geometry, String(NORMAL), 0, 0, -1, 0)
    assert_equal(geometry.attribute_view(String(UV)).component(3, 0), 1)
    assert_equal(geometry.attribute_view(String(UV)).component(3, 1), 1)


def test_sections_of_no_length_spread_evenly() raises:
    """Sections on one point spread the texture by count, as three.js
    does when a total length is zero."""
    var point = Vector3(1, 2, 3)
    var section: List[Vector3] = [point, point, point]
    var geometry = loft([section.copy(), section.copy(), section^], False)
    ref uv = geometry.attribute_view(String(UV))
    assert_almost_equal(uv.component(3, 0), 0.5, atol=1e-6)
    assert_almost_equal(uv.component(1, 1), 0.5, atol=1e-6)


def test_a_cap_winding_either_way() raises:
    """A section wound the other way gets its cap flipped to face out, and
    a cap across the x axis takes y for its tangent."""
    var backward: List[Vector3] = [
        Vector3(-1, 0, 1),
        Vector3(-1, 0, -1),
        Vector3(1, 0, -1),
        Vector3(1, 0, 1),
    ]
    var top: List[Vector3] = [
        Vector3(-1, 1, 1),
        Vector3(-1, 1, -1),
        Vector3(1, 1, -1),
        Vector3(1, 1, 1),
    ]
    var geometry = loft([backward^, top^], True, True, False)
    _check(geometry, String(NORMAL), 10, 0, -1, 0)
    var side: List[Vector3] = [
        Vector3(0, 1, 1),
        Vector3(0, 1, -1),
        Vector3(0, -1, -1),
        Vector3(0, -1, 1),
    ]
    var other: List[Vector3] = [
        Vector3(2, 1, 1),
        Vector3(2, 1, -1),
        Vector3(2, -1, -1),
        Vector3(2, -1, 1),
    ]
    var along_x = loft([side^, other^], True, False, True)
    _check(along_x, String(NORMAL), 10, 1, 0, 0)


def test_a_flat_cap_has_no_triangle() raises:
    """A section on a line has no area, and earcut cuts no triangle."""
    var line: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
    ]
    var raised: List[Vector3] = [
        Vector3(0, 1, 0),
        Vector3(1, 1, 0),
        Vector3(2, 1, 0),
    ]
    var geometry = loft([line^, raised^], False, True)
    assert_equal(geometry.vertex_count(), 6 + 3)
    assert_equal(len(geometry.index), 12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
