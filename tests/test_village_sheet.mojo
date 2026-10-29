# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sheet of triangles: its vertices, its quads and boxes, and the
geometry it becomes."""

from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from extensions.village.sheet import Sheet
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def _normal_of(sheet: Sheet, vertex: Int) -> Vector3:
    """Return a vertex's normal."""
    return Vector3(
        sheet.normals[vertex * 3],
        sheet.normals[vertex * 3 + 1],
        sheet.normals[vertex * 3 + 2],
    )


def test_a_quad_faces_the_way_it_winds() raises:
    var sheet = Sheet(2)
    sheet.quad(
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(4, 2, 0),
        Vector3(0, 2, 0),
        Vector3(0.5, 0.5, 0.5),
    )
    assert_equal(sheet.triangles(), 2)
    assert_almost_equal(_normal_of(sheet, 0).z, 1, atol=1e-6)
    # Texture coordinates are meters over the tile.
    assert_almost_equal(sheet.uvs[2], 2, atol=1e-6)
    assert_almost_equal(sheet.uvs[7], 1, atol=1e-6)
    # Four points on one line face up.
    var line = Sheet(1)
    line.quad(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(3, 0, 0),
        Vector3(1, 1, 1),
    )
    assert_almost_equal(_normal_of(line, 0).y, 1, atol=1e-6)


def test_a_painted_quad_keeps_each_corners_color_and_place() raises:
    var sheet = Sheet(1)
    sheet.painted_quad(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(1, 1, 1),
        3,
        4,
        5,
        6,
    )
    assert_almost_equal(sheet.colors[4], 1, atol=1e-6)
    assert_almost_equal(sheet.colors[8], 1, atol=1e-6)
    # The third corner has the second u and the second v.
    assert_almost_equal(sheet.uvs[4], 5, atol=1e-6)
    assert_almost_equal(sheet.uvs[5], 6, atol=1e-6)
    assert_equal(sheet.index[3], 0)
    assert_equal(sheet.index[5], 3)


def test_a_box_faces_out_on_every_side() raises:
    var sheet = Sheet(1)
    var center = Vector3(1, 2, 3)
    sheet.box(
        center,
        Vector3(0.5, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 2),
        Vector3(1, 1, 1),
    )
    assert_equal(sheet.triangles(), 12)
    for face in range(6):
        var v = face * 4
        var p = Vector3(
            sheet.positions[v * 3],
            sheet.positions[v * 3 + 1],
            sheet.positions[v * 3 + 2],
        )
        var n = _normal_of(sheet, v)
        # Each face's normal points away from the box's middle.
        assert_true((p - center).dot(n) > 0)
    var geometry = sheet.geometry()
    assert_equal(geometry.vertex_count(), 24)
    assert_equal(len(geometry.index), 36)
    for name in [POSITION, NORMAL, COLOR, UV]:
        assert_true(geometry.has_attribute(String(name)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
