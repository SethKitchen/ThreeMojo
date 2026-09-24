# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.text`: text set in a font and extruded.

The vertex counts and bounding boxes come from three.js 0.180's
`TextGeometry` on `assets/fonts/fixture.typeface.json`.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.text import text_geometry
from loaders.font import read_font
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime FIXTURE = "assets/fonts/fixture.typeface.json"
comptime TEXT = "AO i8\nD?é"


def assert_box(
    geometry: BufferGeometry,
    low_x: Float32,
    low_y: Float32,
    low_z: Float32,
    high_x: Float32,
    high_y: Float32,
    high_z: Float32,
) raises:
    """Assert a geometry's bounding box, to three.js's four decimals."""
    var box = geometry.bounding_box()
    assert_almost_equal(box.min.x, low_x, atol=1e-3)
    assert_almost_equal(box.min.y, low_y, atol=1e-3)
    assert_almost_equal(box.min.z, low_z, atol=1e-3)
    assert_almost_equal(box.max.x, high_x, atol=1e-3)
    assert_almost_equal(box.max.y, high_y, atol=1e-3)
    assert_almost_equal(box.max.z, high_z, atol=1e-3)


def test_text_matches_three_js() raises:
    var font = read_font(FIXTURE)
    var geometry = text_geometry(
        TEXT, font, Length(100, METER), Length(5, METER)
    )
    assert_equal(geometry.vertex_count(), 1932)
    assert_false(geometry.is_indexed())
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_equal(geometry.attribute_view(String(UV)).count(), 1932)
    assert_box(geometry, 0, -95, 0, 217, 80, 5)


def test_beveled_text_matches_three_js() raises:
    var font = read_font(FIXTURE)
    var geometry = text_geometry(
        TEXT,
        font,
        Length(100, METER),
        Length(5, METER),
        curve_segments=4,
        steps=2,
        bevel_enabled=True,
        bevel_thickness=Length(1, METER),
        bevel_size=Length(0.5, METER),
        bevel_segments=2,
    )
    assert_equal(geometry.vertex_count(), 3522)
    assert_box(geometry, -0.5754, -95.5, -1, 217.5, 80.5, 6)


def test_the_defaults_are_three_js_s() raises:
    var font = read_font(FIXTURE)
    var geometry = text_geometry("A8", font, Length(2, METER))
    assert_equal(geometry.vertex_count(), 324)
    assert_box(geometry, 0, 0, 0, 2.04, 1.6, 50)
    # Two groups a shape, caps then walls, as three.js's `ExtrudeGeometry`.
    ref groups = geometry.groups
    # Three shapes: the A, and the 8 as two.
    assert_equal(len(groups), 6)
    var start = 0
    for index in range(6):
        assert_equal(groups[index].start, start)
        assert_equal(groups[index].material_index.value, index % 2)
        start += groups[index].count
    assert_equal(start, 324)
    var round = text_geometry(
        "O", font, Length(1, METER), Length(0.1, METER), curve_segments=3
    )
    assert_equal(round.vertex_count(), 288)
    assert_box(round, 0.05, 0.05, 0, 0.65, 0.65, 0.1)


def test_text_with_nothing_to_draw_is_empty() raises:
    var font = read_font(FIXTURE)
    var geometry = text_geometry(" \n ", font)
    assert_equal(geometry.vertex_count(), 0)
    assert_equal(geometry.attribute_view(String(POSITION)).count(), 0)
    assert_equal(geometry.attribute_view(String(NORMAL)).count(), 0)
    assert_equal(geometry.attribute_view(String(UV)).count(), 0)


def test_the_options_are_checked_even_with_nothing_to_draw() raises:
    var font = read_font(FIXTURE)
    with assert_raises(contains="positive depth"):
        _ = text_geometry(" ", font, depth=Length(0, METER))
    with assert_raises(contains="one step"):
        _ = text_geometry(" ", font, steps=0)
    with assert_raises(contains="one curve segment"):
        _ = text_geometry(" ", font, curve_segments=0)
    with assert_raises(contains="one band"):
        _ = text_geometry(" ", font, bevel_enabled=True, bevel_segments=0)
    with assert_raises(contains="positive thickness"):
        _ = text_geometry(
            " ", font, bevel_enabled=True, bevel_thickness=Length(0, METER)
        )
    with assert_raises(contains="negative distance"):
        _ = text_geometry(
            " ", font, bevel_enabled=True, bevel_size=Length(-1, METER)
        )
    with assert_raises(contains="must be positive"):
        _ = text_geometry("A", font, Length(0, METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
