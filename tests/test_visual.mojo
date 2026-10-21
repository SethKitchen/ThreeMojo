# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.visual`: the mesh builder, the frame overlay and
the civil-works textures."""

from std.collections import Dict
from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from extensions.visual.mesh import MeshBuilder
from extensions.visual.overlay import (
    CENTER,
    RIGHT,
    Overlay,
    arrow,
    fill_disc,
    fill_polygons,
    fill_rect,
    stroke_line,
)
from extensions.visual.textures import (
    formed_concrete_maps,
    riprap_maps,
    soil_maps,
)
from generators.utils import Vec3d
from loaders.font import Font, Glyph, LINE_TO, MOVE_TO, OutlineStep
from render.framebuffer import Color, Framebuffer

comptime FONT = "assets/ttf/kenpixel.ttf"


def _normal(mb: MeshBuilder, tri: Int) -> Vec3d:
    """The stored normal of a triangle's first corner, back in z up."""
    var i = 9 * tri
    return Vec3d(
        Float64(mb.normals[i]),
        -Float64(mb.normals[i + 2]),
        Float64(mb.normals[i + 1]),
    )


def _corner(mb: MeshBuilder, tri: Int) -> Vec3d:
    var i = 9 * tri
    return Vec3d(
        Float64(mb.positions[i]),
        -Float64(mb.positions[i + 2]),
        Float64(mb.positions[i + 1]),
    )


def test_triangles_and_frames() raises:
    var mb = MeshBuilder()
    mb.triangle(Vec3d(0, 0, 0), Vec3d(1, 0, 0), Vec3d(0, 1, 0), Vec3d(1, 1, 1))
    assert_equal(mb.count(), 1)
    # z up becomes y up: the face up in z is up in y.
    assert_almost_equal(Float64(mb.normals[1]), 1.0, atol=1e-6)
    mb.triangle(Vec3d(0, 0, 0), Vec3d(1, 0, 0), Vec3d(2, 0, 0), Vec3d(1, 1, 1))
    assert_equal(mb.count(), 1)
    mb.quad(
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 0, 1),
        Vec3d(0, 0, 1),
        Vec3d(1, 0, 0),
    )
    assert_equal(mb.count(), 3)
    mb.oriented(
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, -1),
        Vec3d(1, 1, 1),
    )
    assert_almost_equal(_normal(mb, 3).z, -1.0, atol=1e-6)
    var g = mb.geometry()
    assert_true(g.has_attribute(String(POSITION)))
    assert_true(g.has_attribute(String(NORMAL)))
    assert_true(g.has_attribute(String(UV)))
    assert_true(g.has_attribute(String(COLOR)))
    # A smooth triangle of no area is skipped too.
    var n = Vec3d(0, 0, 1)
    var white = Vec3d(1, 1, 1)
    mb.smooth_triangle(
        Vec3d(0, 0, 0),
        Vec3d(1, 1, 0),
        Vec3d(2, 2, 0),
        n,
        n,
        n,
        white,
        white,
        white,
    )
    assert_equal(mb.count(), 4)


def test_prism_faces_outward() raises:
    var mb = MeshBuilder()
    var square: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
    ]
    mb.prism(
        square, Vec3d(0, 0, 0), Vec3d(0, 2, 0), Vec3d(1, 0, 0), Vec3d(1, 1, 1)
    )
    assert_equal(mb.count(), 12)
    var center = Vec3d(0.5, 1.0, 0.5)
    for t in range(mb.count()):
        var out = _corner(mb, t) - center
        assert_true(_normal(mb, t).dot(out) > 0)
    # Run the other way, and no caps.
    var back = MeshBuilder()
    back.prism(
        square,
        Vec3d(0, 2, 0),
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 1, 1),
        False,
    )
    assert_equal(back.count(), 8)
    for t in range(back.count()):
        assert_true(_normal(back, t).dot(_corner(back, t) - center) > 0)
    # The other way with caps: the caps face outward too.
    var capped = MeshBuilder()
    capped.prism(
        square, Vec3d(0, 2, 0), Vec3d(0, 0, 0), Vec3d(1, 0, 0), Vec3d(1, 1, 1)
    )
    assert_equal(capped.count(), 12)
    for t in range(capped.count()):
        assert_true(_normal(capped, t).dot(_corner(capped, t) - center) > 0)


def test_loft_refusals() raises:
    var mb = MeshBuilder()
    var tri: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (0.0, 1.0),
    ]
    var two: List[Tuple[Float64, Float64]] = [(0.0, 0.0), (1.0, 0.0)]
    with assert_raises(contains="three points"):
        mb.prism(
            two, Vec3d(0, 0, 0), Vec3d(0, 1, 0), Vec3d(1, 0, 0), Vec3d(1, 1, 1)
        )
    with assert_raises(contains="same points"):
        mb.loft(
            tri,
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            two,
            Vec3d(0, 1, 0),
            Vec3d(1, 0, 0),
            Vec3d(1, 1, 1),
        )
    var bad: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, nan[DType.float64]()),
        (0.0, 1.0),
    ]
    with assert_raises(contains="finite"):
        mb.prism(
            bad, Vec3d(0, 0, 0), Vec3d(0, 1, 0), Vec3d(1, 0, 0), Vec3d(1, 1, 1)
        )
    # A bad u at the start, and a bad u or v at the end only.
    var bad_u: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (inf[DType.float64](), 0.0),
        (0.0, 1.0),
    ]
    var bad_v: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, inf[DType.float64]()),
        (0.0, 1.0),
    ]
    with assert_raises(contains="finite"):
        mb.prism(
            bad_u,
            Vec3d(0, 0, 0),
            Vec3d(0, 1, 0),
            Vec3d(1, 0, 0),
            Vec3d(1, 1, 1),
        )
    with assert_raises(contains="finite"):
        mb.loft(
            tri,
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            bad_u,
            Vec3d(0, 1, 0),
            Vec3d(1, 0, 0),
            Vec3d(1, 1, 1),
        )
    with assert_raises(contains="finite"):
        mb.loft(
            tri,
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            bad_v,
            Vec3d(0, 1, 0),
            Vec3d(1, 0, 0),
            Vec3d(1, 1, 1),
        )
    # A mitered, tapered loft.
    var top: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (0.0, 2.0),
    ]
    mb.loft(
        tri,
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        top,
        Vec3d(0, 1, 0),
        Vec3d(1.2, 0.3, 0),
        Vec3d(1, 1, 1),
    )
    assert_equal(mb.count(), 8)


def test_plate_with_hole() raises:
    var mb = MeshBuilder()
    var outline: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (0.0, 4.0),
        (4.0, 4.0),
        (4.0, 0.0),
    ]
    var hole: List[Tuple[Float64, Float64]] = [
        (1.0, 1.0),
        (3.0, 1.0),
        (3.0, 3.0),
        (1.0, 3.0),
    ]
    var holes = List[List[Tuple[Float64, Float64]]]()
    holes.append(hole^)
    mb.plate(
        outline,
        holes,
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 0, 1),
        Vec3d(0, 0.5, 0),
        Vec3d(1, 1, 1),
    )
    # 8 cap triangles a face, 2 faces, and 8 walls of 2 triangles.
    assert_equal(mb.count(), 32)
    var area = Float64(0)
    for t in range(mb.count()):
        var n = _normal(mb, t)
        if n.y < -0.99:
            var a = _corner(mb, t)
            var i = 9 * t
            var b = Vec3d(
                Float64(mb.positions[i + 3]),
                -Float64(mb.positions[i + 5]),
                Float64(mb.positions[i + 4]),
            )
            var c = Vec3d(
                Float64(mb.positions[i + 6]),
                -Float64(mb.positions[i + 8]),
                Float64(mb.positions[i + 7]),
            )
            var cr = (b - a).cross(c - a)
            area += 0.5 * sqrt(cr.dot(cr))
    assert_almost_equal(area, 12.0, atol=1e-5)
    # A counterclockwise outline with no holes: two caps of two triangles
    # and four walls of two.
    var solid = MeshBuilder()
    var ccw: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (4.0, 0.0),
        (4.0, 4.0),
        (0.0, 4.0),
    ]
    var no_holes = List[List[Tuple[Float64, Float64]]]()
    solid.plate(
        ccw,
        no_holes,
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 0, 1),
        Vec3d(0, 0.5, 0),
        Vec3d(1, 1, 1),
    )
    assert_equal(solid.count(), 12)
    # earcut refuses a hole of no points.
    var empty_hole = MeshBuilder()
    var holes_of_none = List[List[Tuple[Float64, Float64]]]()
    holes_of_none.append(List[Tuple[Float64, Float64]]())
    with assert_raises(contains="hole must start"):
        empty_hole.plate(
            ccw,
            holes_of_none,
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            Vec3d(0, 0, 1),
            Vec3d(0, 0.5, 0),
            Vec3d(1, 1, 1),
        )
    assert_equal(empty_hole.count(), 0)
    # An outline of no area has no caps, only its three walls.
    var flat = MeshBuilder()
    var line: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (2.0, 0.0),
    ]
    flat.plate(
        line,
        no_holes,
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 0, 1),
        Vec3d(0, 0.5, 0),
        Vec3d(1, 1, 1),
    )
    assert_equal(flat.count(), 6)
    with assert_raises(contains="three points"):
        mb.plate(
            [(0.0, 0.0), (1.0, 0.0)],
            List[List[Tuple[Float64, Float64]]](),
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            Vec3d(0, 0, 1),
            Vec3d(0, 1, 0),
            Vec3d(1, 1, 1),
        )


def test_tube() raises:
    var mb = MeshBuilder()
    mb.tube(
        Vec3d(0, 0, 0),
        Vec3d(0, 0, 2),
        1.0,
        0.5,
        8,
        Vec3d(1, 1, 1),
        Vec3d(0, 0, 0),
    )
    assert_equal(mb.count(), 8 * 8)
    var rod = MeshBuilder()
    rod.tube(
        Vec3d(0, 0, 0),
        Vec3d(2, 0, 0),
        1.0,
        0.0,
        6,
        Vec3d(1, 1, 1),
        Vec3d(0, 0, 0),
    )
    assert_equal(rod.count(), 6 * 4)
    with assert_raises(contains="three segments"):
        rod.tube(
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            1.0,
            0.0,
            2,
            Vec3d(1, 1, 1),
            Vec3d(0, 0, 0),
        )
    with assert_raises(contains="radii"):
        rod.tube(
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            1.0,
            1.0,
            6,
            Vec3d(1, 1, 1),
            Vec3d(0, 0, 0),
        )
    with assert_raises(contains="radii"):
        rod.tube(
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            0.0,
            0.0,
            6,
            Vec3d(1, 1, 1),
            Vec3d(0, 0, 0),
        )
    with assert_raises(contains="radii"):
        rod.tube(
            Vec3d(0, 0, 0),
            Vec3d(1, 0, 0),
            1.0,
            -0.5,
            6,
            Vec3d(1, 1, 1),
            Vec3d(0, 0, 0),
        )
    with assert_raises(contains="must differ"):
        rod.tube(
            Vec3d(0, 0, 0),
            Vec3d(0, 0, 0),
            1.0,
            0.0,
            6,
            Vec3d(1, 1, 1),
            Vec3d(0, 0, 0),
        )


def test_heightfield() raises:
    var mb = MeshBuilder()
    var h: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
    mb.heightfield(Vec3d(0, 0, 0), 1.0, 1.0, 3, 2, h, List[Vec3d]())
    assert_equal(mb.count(), 4)
    var colors: List[Vec3d] = [
        Vec3d(1, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 1, 0),
    ]
    mb.heightfield(Vec3d(0, 0, 0), 1.0, 1.0, 3, 2, h, colors)
    assert_equal(mb.count(), 8)
    with assert_raises(contains="2 by 2"):
        mb.heightfield(
            Vec3d(0, 0, 0), 1.0, 1.0, 1, 2, [0.0, 0.0], List[Vec3d]()
        )
    with assert_raises(contains="larger than this port"):
        mb.heightfield(
            Vec3d(0, 0, 0),
            1.0,
            1.0,
            1 << 32,
            1 << 32,
            List[Float64](),
            List[Vec3d](),
        )
    with assert_raises(contains="2 by 2"):
        mb.heightfield(
            Vec3d(0, 0, 0), 1.0, 1.0, 2, 1, [0.0, 0.0], List[Vec3d]()
        )
    with assert_raises(contains="spacing"):
        mb.heightfield(Vec3d(0, 0, 0), 0.0, 1.0, 3, 2, h, List[Vec3d]())
    with assert_raises(contains="spacing"):
        mb.heightfield(Vec3d(0, 0, 0), 1.0, -1.0, 3, 2, h, List[Vec3d]())
    with assert_raises(contains="one height"):
        mb.heightfield(Vec3d(0, 0, 0), 1.0, 1.0, 3, 2, [0.0], List[Vec3d]())
    with assert_raises(contains="one color"):
        mb.heightfield(Vec3d(0, 0, 0), 1.0, 1.0, 3, 2, h, [Vec3d(1, 1, 1)])


def test_fills() raises:
    var fb = Framebuffer(20, 20, Color(0, 0, 0))
    fill_rect(fb, 2, 2, 6, 6, Color(200, 100, 50))
    var inside = fb.get_pixel(3, 3)
    assert_equal(Int(inside.r), 200)
    assert_equal(Int(fb.get_pixel(10, 10).r), 0)
    # A rectangle half over a pixel half covers it.
    fill_rect(fb, 10, 10, 10.5, 11, Color(255, 255, 255))
    var half = Int(fb.get_pixel(10, 10).r)
    assert_true(half > 100 and half < 160)
    fill_rect(fb, 0, 15, 20, 16, Color(255, 0, 0), 0.5)
    assert_true(Int(fb.get_pixel(5, 15).r) > 100)
    stroke_line(fb, 1, 18, 18, 18, 1.5, Color(0, 255, 0))
    assert_true(Int(fb.get_pixel(9, 18).g) > 0)
    stroke_line(fb, 4, 4, 4, 4, 2, Color(9, 9, 9))
    fill_disc(fb, 15, 5, 3, Color(0, 0, 255))
    assert_true(Int(fb.get_pixel(15, 5).b) > 200)
    arrow(fb, 2, 12, 18, 12, 1.0, Color(255, 255, 0))
    arrow(fb, 2, 12, 2, 12, 1.0, Color(255, 255, 0))
    # Off the frame, and empty, draw nothing.
    fill_rect(fb, 40, 40, 50, 50, Color(1, 2, 3))
    fill_polygons(fb, List[List[Tuple[Float64, Float64]]](), Color(1, 2, 3))
    with assert_raises(contains="finite"):
        fill_rect(fb, 0, 0, nan[DType.float64](), 1, Color(1, 1, 1))
    with assert_raises(contains="finite"):
        fill_rect(fb, 0, 0, 1, inf[DType.float64](), Color(1, 1, 1))


def test_fill_edge_cases() raises:
    var fb = Framebuffer(20, 20, Color(0, 0, 0))
    # Above the frame, over its columns: nothing to draw.
    fill_rect(fb, 2, -10, 6, -5, Color(9, 9, 9))
    for x in range(20):
        assert_equal(Int(fb.get_pixel(x, 0).r), 0)
    # An empty ring beside a square draws the square.
    var square: List[Tuple[Float64, Float64]] = [
        (2.0, 2.0),
        (6.0, 2.0),
        (6.0, 6.0),
        (2.0, 6.0),
    ]
    var rings = List[List[Tuple[Float64, Float64]]]()
    rings.append(List[Tuple[Float64, Float64]]())
    rings.append(square.copy())
    fill_polygons(fb, rings, Color(200, 0, 0))
    assert_equal(Int(fb.get_pixel(3, 3).r), 200)
    # A ring only an empty one: nothing to draw.
    var none = List[List[Tuple[Float64, Float64]]]()
    none.append(List[Tuple[Float64, Float64]]())
    fill_polygons(fb, none, Color(1, 2, 3))
    # A span left of the frame, on the same rows as one inside it.
    var left: List[Tuple[Float64, Float64]] = [
        (-10.0, 10.0),
        (-5.0, 10.0),
        (-5.0, 14.0),
        (-10.0, 14.0),
    ]
    var inside: List[Tuple[Float64, Float64]] = [
        (8.0, 10.0),
        (12.0, 10.0),
        (12.0, 14.0),
        (8.0, 14.0),
    ]
    var pair = List[List[Tuple[Float64, Float64]]]()
    pair.append(left^)
    pair.append(inside^)
    fill_polygons(fb, pair, Color(0, 200, 0))
    assert_equal(Int(fb.get_pixel(9, 11).g), 200)
    assert_equal(Int(fb.get_pixel(0, 11).g), 0)


def test_an_overlay_past_an_integer_lies_past_the_frame() raises:
    var fb = Framebuffer(4, 4, Color(0, 0, 0))
    # Entirely to the right of every frame.
    fill_rect(fb, 1e20, 0, 1e20, 2, Color(255, 0, 0))
    assert_equal(Int(fb.get_pixel(0, 0).r), 0)
    # A rectangle from past the left to past the right covers the frame.
    # A floor of 1e20 is not a column, so the old box could miss it.
    fill_rect(fb, -1e20, -1e20, 1e20, 1e20, Color(0, 180, 0))
    assert_equal(Int(fb.get_pixel(0, 0).g), 180)
    assert_equal(Int(fb.get_pixel(3, 3).g), 180)


def test_text() raises:
    var ov = Overlay.from_ttf(FONT)
    var fb = Framebuffer(120, 40, Color(0, 0, 0))
    var w = ov.text_width("A8", 16)
    assert_true(w > 4)
    assert_almost_equal(ov.text_width("", 16), 0.0, atol=1e-12)
    ov.text(fb, "A8", 4, 20, 16, Color(255, 255, 255))
    ov.text(fb, "A8", 60, 20, 16, Color(255, 255, 255), CENTER)
    ov.text(fb, "A8", 116, 20, 16, Color(255, 255, 255), RIGHT)
    ov.text(fb, " ", 4, 20, 16, Color(255, 255, 255))
    var lit = 0
    for y in range(40):
        for x in range(120):
            if Int(fb.get_pixel(x, y).r) > 128:
                lit += 1
    assert_true(lit > 20)
    var size = ov.label(
        fb,
        ["A", "88"],
        2,
        22,
        8,
        Color(255, 255, 255),
        Color(0, 0, 0),
        accent=Color(255, 0, 0),
    )
    assert_true(size[0] > 0 and size[1] > 0)
    var plain = ov.label(
        fb, ["A"], 2, 22, 8, Color(255, 255, 255), Color(0, 0, 0)
    )
    assert_true(plain[0] < size[0])
    # A line break alone, and no lines at all, draw no text.
    assert_almost_equal(ov.text_width("\n", 16), 0.0, atol=0)
    var bare = ov.label(
        fb, List[String](), 2, 22, 8, Color(255, 255, 255), Color(0, 0, 0)
    )
    assert_true(bare[0] > 0 and bare[0] < plain[0])


def test_text_drops_open_contours() raises:
    # A glyph that is one stroke, not a closed outline, has no ring to fill.
    var glyphs = Dict[String, Glyph]()
    glyphs["-"] = Glyph(
        1.0,
        [
            OutlineStep(MOVE_TO, [Float32(0), Float32(0)]),
            OutlineStep(LINE_TO, [Float32(1), Float32(0)]),
        ],
    )
    var ov = Overlay(Font("stroke", 1.0, 0.0, 1.0, 0.0, glyphs^))
    assert_almost_equal(ov.text_width("-", 16), 0.0, atol=0)
    var fb = Framebuffer(8, 8, Color(0, 0, 0))
    ov.text(fb, "-", 1, 4, 16, Color(255, 255, 255))
    assert_equal(Int(fb.get_pixel(2, 4).r), 0)


def test_textures() raises:
    var c = formed_concrete_maps(8, 1, 2)
    assert_equal(c.color.width, 8)
    assert_equal(c.normal.height, 8)
    var s = soil_maps(4)
    assert_equal(s.roughness.width, 4)
    var r = riprap_maps(8, 2)
    assert_equal(r.color.width, 8)
    with assert_raises(contains="at least one texel"):
        _ = soil_maps(0)
    with assert_raises(contains="one panel"):
        _ = formed_concrete_maps(4, 0)
    with assert_raises(contains="one tie"):
        _ = formed_concrete_maps(4, 1, 0)
    with assert_raises(contains="one stone"):
        _ = riprap_maps(4, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
