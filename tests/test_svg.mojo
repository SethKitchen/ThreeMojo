# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.svg`, `loaders.svg_path` and `loaders.svg_shapes`.

`assets/svg/fixture.json` is what three.js 0.180's `SVGLoader` gives for
`assets/svg/fixture.svg` in node: each path's color, style, curves and
points, its `createShapes` and its `pointsToStroke`. The first test
compares all of it. The others reach every branch and every refusal.
"""

from core.buffer_geometry import NORMAL, POSITION, UV
from loaders.json import JsonDocument, parse_json
from loaders.svg import (
    SVG_CM,
    SVG_IN,
    SVG_MM,
    SVG_PC,
    SVG_PT,
    SVG_PX,
    SvgUnit,
    js_parse_float,
    parse_arc_command,
    parse_css_declarations,
    parse_css_rules,
    parse_floats,
    parse_path_data,
    parse_svg,
    read_svg,
    svg_point_pairs,
    svg_unit,
    svg_unit_scale,
)
from loaders.svg_path import (
    SvgCurve,
    SvgMatrix,
    SvgShapePath,
    SvgStyle,
    SvgSubPath,
    SvgVector,
    eigen_decomposition,
    is_transform_flipped,
    is_transform_skewed,
    js_remainder,
    transform_path,
)
from loaders.svg_shapes import (
    SVG_CAP_BUTT,
    SVG_CAP_ROUND,
    SVG_CAP_SQUARE,
    SVG_EVENODD,
    SVG_JOIN_BEVEL,
    SVG_JOIN_MITER,
    SVG_JOIN_MITER_CLIP,
    SVG_JOIN_ROUND,
    SVG_NONZERO,
    SvgFillRule,
    SvgLineCap,
    SvgLineJoin,
    SvgShape,
    SvgStrokeStyle,
    create_shapes,
    create_shapes_with_rule,
    LOCATION_BEHIND,
    LOCATION_BETWEEN,
    LOCATION_BEYOND,
    LOCATION_DESTINATION,
    LOCATION_LEFT,
    LOCATION_ORIGIN,
    LOCATION_RIGHT,
    PointLocation,
    classify_point,
    find_edge_intersection,
    points_to_stroke,
    remove_duplicated_points,
    shape_area,
    svg_fill_rule,
    svg_line_cap,
    svg_line_join,
    to_precision_10,
)
from math.curve import CUBIC, ELLIPSE, LINE, QUADRATIC, SPLINE, CurveKind
from std.math import inf, isnan, nan, pi

from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64, tolerance: Float64 = 1e-9) raises:
    """Assert two numbers agree within a tolerance relative to their size."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= tolerance * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check_numbers(
    doc: JsonDocument, node: Int, got: List[Float64], tolerance: Float64
) raises:
    """Assert a list of numbers matches a JSON array."""
    assert_equal(len(got), doc.length(node))
    for i in range(len(got)):
        near(got[i], doc.number(doc.at(node, i)), tolerance)


def flat(points: List[SvgVector]) -> List[Float64]:
    """Return points as x, y, x, y, ..."""
    var out = List[Float64]()
    for p in points:
        out.append(p[0])
        out.append(p[1])
    return out^


def text_or_null(doc: JsonDocument, node: Int) raises -> String:
    """Return a JSON string, or empty for null."""
    if doc.is_null(node):
        return String()
    return doc.string(node)


def curve_name(kind: CurveKind) -> String:
    """Return three.js's type name of a curve."""
    if kind == LINE:
        return "LineCurve"
    if kind == QUADRATIC:
        return "QuadraticBezierCurve"
    if kind == CUBIC:
        return "CubicBezierCurve"
    return "ellipse"


def check_path(
    doc: JsonDocument, want: Int, got: SvgShapePath, name: String
) raises:
    """Compare one shape path with three.js's."""
    assert_equal(name, doc.string(doc.get(want, "node")))
    var color = doc.get(want, "color")
    near(Float64(got.color.r), doc.number(doc.at(color, 0)), 1e-6)
    near(Float64(got.color.g), doc.number(doc.at(color, 1)), 1e-6)
    near(Float64(got.color.b), doc.number(doc.at(color, 2)), 1e-6)
    var style = doc.get(want, "style")
    ref s = got.style
    assert_equal(s.fill, text_or_null(doc, doc.get(style, "fill")))
    near(s.fill_opacity, doc.number(doc.get(style, "fillOpacity")))
    assert_equal(s.fill_rule, text_or_null(doc, doc.get(style, "fillRule")))
    var opacity = doc.get(style, "opacity")
    assert_equal(s.has_opacity, not doc.is_null(opacity))
    if s.has_opacity:
        near(s.opacity, doc.number(opacity))
    assert_equal(s.stroke, text_or_null(doc, doc.get(style, "stroke")))
    near(s.stroke_opacity, doc.number(doc.get(style, "strokeOpacity")))
    near(s.stroke_width, doc.number(doc.get(style, "strokeWidth")))
    assert_equal(
        s.stroke_line_join, doc.string(doc.get(style, "strokeLineJoin"))
    )
    assert_equal(s.stroke_line_cap, doc.string(doc.get(style, "strokeLineCap")))
    near(s.stroke_miter_limit, doc.number(doc.get(style, "strokeMiterLimit")))
    assert_equal(s.visibility, text_or_null(doc, doc.get(style, "visibility")))

    var subs = doc.get(want, "subPaths")
    assert_equal(len(got.sub_paths), doc.length(subs))
    for i in range(len(got.sub_paths)):
        ref sub = got.sub_paths[i]
        var w = doc.at(subs, i)
        assert_equal(sub.auto_close, doc.boolean(doc.get(w, "autoClose")))
        var curves = doc.get(w, "curves")
        assert_equal(len(sub.curves), doc.length(curves))
        for j in range(len(sub.curves)):
            ref c = sub.curves[j]
            var wc = doc.at(curves, j)
            assert_equal(curve_name(c.kind), doc.string(doc.get(wc, "type")))
            var values = flat(c.points)
            if c.kind == ELLIPSE:
                values.append(c.x_radius)
                values.append(c.y_radius)
                values.append(c.start_angle)
                values.append(c.end_angle)
                values.append(Float64(1) if c.clockwise else Float64(0))
                values.append(c.rotation)
            check_numbers(doc, doc.get(wc, "v"), values, 1e-9)
        check_numbers(doc, doc.get(w, "points"), flat(sub.get_points()), 1e-9)

    var shapes = doc.get(want, "shapes")
    var made = create_shapes(got)
    assert_equal(len(made), doc.length(shapes))
    for i in range(len(made)):
        var ws = doc.at(shapes, i)
        check_numbers(
            doc,
            doc.get(ws, "outline"),
            flat(made[i].outline.get_points()),
            1e-9,
        )
        var holes = doc.get(ws, "holes")
        assert_equal(len(made[i].holes), doc.length(holes))
        for h in range(len(made[i].holes)):
            check_numbers(
                doc, doc.at(holes, h), flat(made[i].holes[h].get_points()), 1e-9
            )

    var strokes = doc.get(want, "strokes")
    for i in range(len(got.sub_paths)):
        var ws = doc.at(strokes, i)
        if doc.is_null(ws):
            continue
        var stroke = points_to_stroke(
            got.sub_paths[i].get_points(), SvgStrokeStyle(got.style)
        )
        check_numbers(doc, doc.get(ws, "position"), stroke.vertices, 1e-5)
        check_numbers(doc, doc.get(ws, "uv"), stroke.uvs, 1e-5)


def test_the_fixture_matches_three_js() raises:
    # The strokes of paths 2 and 3 are left out of the JSON. Their curves
    # meet in line, where a join's miter is a quotient of two roundings,
    # and Mojo fuses a multiply and an add that JavaScript rounds twice.
    var data = read_svg("assets/svg/fixture.svg")
    var doc = parse_json(Path("assets/svg/fixture.json").read_text())
    var paths = doc.get(doc.root(), "paths")
    assert_equal(len(data.paths), doc.length(paths))
    for i in range(len(data.paths)):
        check_path(
            doc,
            doc.at(paths, i),
            data.paths[i],
            data.document.name(data.paths[i].node),
        )


def test_strokes_match_three_js() raises:
    var doc = parse_json(Path("assets/svg/strokes.json").read_text())
    var cases = doc.get(doc.root(), "strokes")
    for i in range(doc.length(cases)):
        var c = doc.at(cases, i)
        var raw = doc.get(c, "points")
        var points = List[SvgVector]()
        for k in range(0, doc.length(raw), 2):
            points.append(
                SvgVector(
                    doc.number(doc.at(raw, k)), doc.number(doc.at(raw, k + 1))
                )
            )
        var style = SvgStrokeStyle(
            doc.number(doc.get(c, "width")),
            svg_line_join(doc.string(doc.get(c, "join"))),
            svg_line_cap(doc.string(doc.get(c, "cap"))),
            doc.number(doc.get(c, "limit")),
        )
        var stroke = points_to_stroke(points, style, 3, 0.001)
        assert_equal(stroke.count, doc.integer(doc.get(c, "count")))
        check_numbers(doc, doc.get(c, "position"), stroke.vertices, 1e-9)
        check_numbers(doc, doc.get(c, "uv"), stroke.uvs, 1e-9)


def test_units() raises:
    assert_true(svg_unit("mm") == SVG_MM)
    assert_true(svg_unit("cm") == SVG_CM)
    assert_true(svg_unit("in") == SVG_IN)
    assert_true(svg_unit("pt") == SVG_PT)
    assert_true(svg_unit("pc") == SVG_PC)
    assert_true(svg_unit("px") == SVG_PX)
    with assert_raises(contains="unit that is not known"):
        _ = svg_unit("em")
    assert_false(SvgUnit(-1).is_valid())
    assert_false(SvgUnit(6).is_valid())
    near(svg_unit_scale(SVG_PX, SVG_PX, 90), 1)
    near(svg_unit_scale(SVG_PX, SVG_MM, 90), 25.4 / 90)
    near(svg_unit_scale(SVG_IN, SVG_PX, 90), 90)
    near(svg_unit_scale(SVG_CM, SVG_PX, 90), 1 / 2.54 * 90)
    near(svg_unit_scale(SVG_MM, SVG_PX, 96), 1 / 25.4 * 96)
    near(svg_unit_scale(SVG_PT, SVG_PC, 90), 6.0 / 72)
    near(svg_unit_scale(SVG_PC, SVG_IN, 90), 1.0 / 6)
    with assert_raises(contains="not valid"):
        _ = svg_unit_scale(SvgUnit(9), SVG_PX, 90)
    with assert_raises(contains="not valid"):
        _ = svg_unit_scale(SVG_PX, SvgUnit(-2), 90)
    with assert_raises(contains="default unit"):
        _ = parse_svg("<svg/>", SvgUnit(7))
    # A length in pixels, read in millimeters, and one in inches.
    var data = parse_svg(
        '<svg><line x1="90" y1="1in" x2="0" y2="0"/></svg>', SVG_MM, 90
    )
    var line = data.paths[0].sub_paths[0].curves[0].points.copy()
    near(line[0][0], 25.4)
    near(line[0][1], 25.4)


def test_js_parse_float() raises:
    near(js_parse_float("  12.5e3xyz"), 12500)
    near(js_parse_float("-.5"), -0.5)
    near(js_parse_float("+7."), 7)
    near(js_parse_float("1e"), 1)
    near(js_parse_float("1E+"), 1)
    near(js_parse_float("2E-1"), 0.2)
    near(js_parse_float("3%"), 3)
    assert_true(js_parse_float("Infinity") > 1e308)
    assert_true(js_parse_float("-Infinity") < -1e308)
    assert_true(js_parse_float("+Infinity") > 1e308)
    assert_true(isnan(js_parse_float("")))
    assert_true(isnan(js_parse_float("  ")))
    assert_true(isnan(js_parse_float(".")))
    assert_true(isnan(js_parse_float("-")))
    assert_true(isnan(js_parse_float("abc")))
    # A number longer than Mojo's parser reads.
    assert_true(isnan(js_parse_float("0" * 60 + "1")))


def check_floats(text: String, want: List[Float64]) raises:
    """Assert `parse_floats` reads a text as numbers."""
    var got = parse_floats(text)
    assert_equal(len(got), len(want))
    for i in range(len(want)):
        near(got[i], want[i])


def test_parse_floats() raises:
    check_floats("1 2,3", [1, 2, 3])
    check_floats(" -1-2+3", [-1, -2, 3])
    check_floats(".5.5", [0.5, 0.5])
    check_floats("1.5.5", [1.5, 0.5])
    check_floats("1e2 1e-2 1E+2", [100, 0.01, 100])
    check_floats("2e1.5", [20, 0.5])
    check_floats("2e1-5", [20, -5])
    check_floats("2e1,5", [20, 5])
    check_floats("2e 3", [2, 3])
    check_floats("1.e2", [100])
    check_floats("\t1\r\n2 ,3", [1, 2, 3])
    check_floats("", [])
    check_floats("-12-3", [-12, -3])
    check_floats("1e+2+3", [100, 3])
    check_floats("1-2", [1, -2])
    # Flags: at positions three and four of seven, a 0 or 1 is a number.
    var arc = parse_floats("5 5 30 1015 -1-2", [3, 4], 7)
    assert_equal(len(arc), 8)
    near(arc[2], 30)
    near(arc[3], 1)
    near(arc[4], 0)
    near(arc[5], 15)
    near(arc[6], -1)
    var signed = parse_floats("1 1 0 -1 1 2 2", [3, 4], 7)
    near(signed[3], 1)
    with assert_raises(contains="unexpected `,`"):
        _ = parse_floats("1,,2")
    with assert_raises(contains="unexpected `,`"):
        _ = parse_floats(",1")
    with assert_raises(contains="unexpected `+`"):
        _ = parse_floats("-+1")
    with assert_raises(contains="unexpected `-`"):
        _ = parse_floats("+-1")
    with assert_raises(contains="unexpected `.`"):
        _ = parse_floats("1..2")
    with assert_raises(contains="unexpected `-`"):
        _ = parse_floats("1e+-2")
    with assert_raises(contains="unexpected `+`"):
        _ = parse_floats("1e-+2")
    with assert_raises(contains="unexpected character"):
        _ = parse_floats("1px")
    with assert_raises(contains="unexpected character"):
        _ = parse_floats("x")
    with assert_raises(contains="not a number"):
        _ = parse_floats("-")
    with assert_raises(contains="not a number"):
        _ = parse_floats("1e-")


def check_pairs(text: String, want: List[String]) raises:
    """Assert the pairs three.js's expression finds."""
    var got = svg_point_pairs(text)
    assert_equal(len(got), len(want))
    for i in range(len(want)):
        assert_equal(got[i], want[i])


def test_point_pairs() raises:
    check_pairs("1,2 3,4", ["1", "2", "3", "4"])
    check_pairs("1-2,3", ["-2", "3"])
    check_pairs("1, 2", [])
    check_pairs("1 2 3", ["1", "2"])
    check_pairs("-1.5e2,+.5e-1x", ["-1.5e2", "+.5e-1"])
    check_pairs("1.,2", [])
    check_pairs("1e,2", [])
    check_pairs("1,e2", [])
    check_pairs("12.5.3,4", ["5.3", "4"])
    check_pairs("7,8.9.", ["7", "8.9"])
    check_pairs("5,6e+", ["5", "6"])
    check_pairs("5 ", [])
    check_pairs("", [])
    check_pairs("a1,2", ["1", "2"])


def test_css() raises:
    var rules = parse_css_rules(
        "/* a */ .a, #b { fill: red; stroke : Blue !important ; x ; y: }"
        + " @media print { .a { fill: none } } .c{fill:green;fill:navy} .d{"
    )
    assert_equal(len(rules), 3)
    assert_equal(rules[0].selectors, ".a, #b")
    assert_equal(len(rules[0].names), 2)
    assert_equal(rules[0].names[1], "stroke")
    assert_equal(rules[0].values[1], "Blue")
    assert_equal(rules[1].values[0], "navy")
    assert_equal(len(rules[1].names), 1)
    assert_equal(rules[2].selectors, ".d")
    var decl = parse_css_declarations("FILL: red; /* not closed")
    assert_equal(decl.names[0], "fill")
    assert_equal(len(parse_css_rules("no rules")), 0)
    assert_equal(len(parse_css_declarations(":a").names), 0)


def test_path_commands() raises:
    # Every command, each first after a close and each twice.
    var path = parse_path_data(
        "M1 1 2 2 Z L3 3 4 4 Z H5 6 Z V7 8 Z C1 2 3 4 5 6 7 8 9 10 11 12 Z"
        + " S1 2 3 4 5 6 7 8 Z Q1 2 3 4 5 6 7 8 Z T1 2 3 4 Z"
        + " A5 5 0 0 1 10 10 5 5 0 1 0 1 1 Z m1 1 1 1 z l1 1 1 1 z h1 1 z"
        + " v1 1 z c1 2 3 4 5 6 1 2 3 4 5 6 z s1 2 3 4 1 2 3 4 z"
        + " q1 2 3 4 1 2 3 4 z t1 2 3 4 z a5 5 0 0 1 3 3 5 5 0 0 1 3 3 z"
    )
    assert_equal(len(path.sub_paths), 2)
    var points = path.sub_paths[0].get_points()
    near(points[0][0], 1)
    assert_true(len(points) > 50)
    # An arc to where the pen is, or by nothing, draws nothing.
    var still = parse_path_data("M1 1 A1 1 0 0 0 1 1 a1 1 0 0 0 0 0")
    assert_equal(len(still.sub_paths[0].curves), 0)
    # An arc with a zero radius is a line.
    var flat = parse_path_data("M0 0 A0 1 0 0 0 5 0 A1 0 0 0 0 5 5")
    assert_equal(len(flat.sub_paths[0].curves), 2)
    assert_true(flat.sub_paths[0].curves[1].kind == LINE)
    # A close with nothing drawn keeps the pen where it is.
    var closed = parse_path_data("M3 3 Z L4 4")
    near(closed.sub_paths[0].curves[0].points[0][0], 3)
    # Commands with no numbers draw nothing.
    var bare = parse_path_data("M1 1 M L H V C S Q T A Z")
    assert_equal(len(bare.sub_paths[0].curves), 0)
    assert_equal(len(parse_path_data("").sub_paths), 0)
    assert_equal(len(parse_path_data("none").sub_paths), 0)
    with assert_raises(contains="no command"):
        _ = parse_path_data("1 2 3")
    with assert_raises(contains="not known"):
        _ = parse_path_data("M0 0 B1 1")
    with assert_raises(contains="groups of 2"):
        _ = parse_path_data("M0 0 1")
    with assert_raises(contains="groups of 2"):
        _ = parse_path_data("M0 0 L1")
    with assert_raises(contains="groups of 6"):
        _ = parse_path_data("M0 0 C1 1")
    with assert_raises(contains="groups of 4"):
        _ = parse_path_data("M0 0 S1 1")
    with assert_raises(contains="groups of 4"):
        _ = parse_path_data("M0 0 Q1 1")
    with assert_raises(contains="groups of 2"):
        _ = parse_path_data("M0 0 T1")
    with assert_raises(contains="groups of 7"):
        _ = parse_path_data("M0 0 A1 1")
    with assert_raises(contains="draws before it moves"):
        _ = parse_path_data("L1 1")
    with assert_raises(contains="draws before it moves"):
        _ = parse_path_data("Z")
    with assert_raises(contains="draws before it moves"):
        _ = parse_path_data("A1 1 0 0 0 5 5")


def test_arc_command() raises:
    # Radii too small for the ends are scaled up, and the large arc and
    # sweep flags pick one of four arcs.
    var path = SvgShapePath()
    path.move_to(0, 0)
    parse_arc_command(path, 1, 1, 0, 0, 0, SvgVector(0, 0), SvgVector(10, 0))
    parse_arc_command(
        path, 20, 10, 45, 1, 0, SvgVector(10, 0), SvgVector(0, 10)
    )
    parse_arc_command(
        path, -20, 10, 45, 1, 1, SvgVector(0, 10), SvgVector(0, 0)
    )
    ref curves = path.sub_paths[0].curves
    near(curves[0].x_radius, 5)
    near(curves[0].points[0][0], 5)
    ref last = curves[len(curves) - 1]
    near(last.x_radius, 20)
    var end = last.point(1)
    near(end[0], 0, 1e-9)
    near(end[1], 0, 1e-9)


def test_elements_and_refusals() raises:
    var svg = String(
        '<svg xmlns:x="http://www.w3.org/1999/xlink" xmlns:y="other">'
        + '<g id="gid" class=" a  b "><path/><path d="none"/>'
        + '<rect width="4" height="2" ry="1"/>'
        + '<rect width="4" height="2" rx="1" ry="0"/></g>'
        + '<circle r="2"/><ellipse rx="3" ry="1"/><line x2="5"/>'
        + '<use x:href="#gid" x="5"/><use y:href="#gid" x:href="#gid" y="1"/>'
        + "<text><polyline points='0,0 1,1'/></text></svg>"
    )
    var data = parse_svg(svg)
    assert_equal(len(data.paths), 10)
    near(data.paths[0].sub_paths[0].curves[1].points[3][1], 1)
    with assert_raises(contains="`width` and a `height`"):
        _ = parse_svg("<svg><rect height='1'/></svg>")
    with assert_raises(contains="`width` and a `height`"):
        _ = parse_svg("<svg><rect width='1'/></svg>")
    with assert_raises(contains="no points"):
        _ = parse_svg("<svg><polygon points='1'/></svg>")
    with assert_raises(contains="names no element"):
        _ = parse_svg("<svg><use/></svg>")
    with assert_raises(contains="names no element"):
        _ = parse_svg(
            '<svg xmlns:x="http://www.w3.org/1999/xlink"><use/></svg>'
        )
    with assert_raises(contains="names no element"):
        _ = parse_svg(
            '<svg xmlns:x="http://www.w3.org/1999/xlink"><use'
            + ' x:href="#no"/></svg>'
        )
    with assert_raises(contains="names no element"):
        _ = parse_svg(
            '<g xmlns:x="http://www.w3.org/1999/xlink"><use x:href="#g"/></g>'
        )
    with assert_raises(contains="draws itself"):
        _ = parse_svg(
            '<svg xmlns:x="http://www.w3.org/1999/xlink"><g id="g">'
            + '<use x:href="#g"/></g></svg>'
        )
    with assert_raises(contains="no parenthesis"):
        _ = parse_svg("<svg><g transform='scale'/></svg>")
    with assert_raises(contains="no parenthesis"):
        _ = parse_svg("<svg><g transform='(1)'/></svg>")
    with assert_raises(contains="is not a number"):
        _ = parse_svg("<svg><circle r='big'/></svg>")
    with assert_raises(contains="is not a number"):
        _ = parse_svg("<svg><g opacity='x'/></svg>")
    with assert_raises():
        _ = parse_svg("<svg>")
    with assert_raises():
        _ = read_svg("assets/svg/missing.svg")


def test_transforms() raises:
    # Transforms of the wrong length are the identity, as in three.js.
    var data = parse_svg(
        "<svg><g transform='translate() rotate() scale() skewX(1 2)"
        + " skewY() matrix(1 2 3) spin(4) translate(3)'>"
        + "<line x2='1'/></g><g transform='scale(2) rotate(90)'>"
        + "<line x2='1'/></g></svg>"
    )
    var first = data.paths[0].sub_paths[0].curves[0].points.copy()
    near(first[0][0], 3)
    near(first[1][0], 4)
    var second = data.paths[1].sub_paths[0].curves[0].points.copy()
    near(second[1][0], 0, 1e-9)
    near(second[1][1], 2)


def test_styles() raises:
    var data = parse_svg(
        "<svg><style>.s { stroke-miterlimit: -2 } #p { visibility: hidden }"
        + "</style><path id='p' class='s' d='M0 0 L1 1' fill='none'"
        + " style='stroke-opacity: 2; opacity: -1; fill-rule: evenodd'"
        + " stroke-width='-1' stroke-linecap='round'/></svg>"
    )
    ref style = data.paths[0].style
    near(style.stroke_miter_limit, 0)
    assert_equal(style.visibility, "hidden")
    near(style.stroke_opacity, 1)
    near(style.opacity, 0)
    assert_true(style.has_opacity)
    assert_equal(style.fill_rule, "evenodd")
    near(style.stroke_width, 0)
    near(Float64(data.paths[0].color.r), 1)
    # An empty class, and a rule with no declarations.
    var plain = parse_svg(
        "<svg><style>.x {}</style><path class='x' d='M0 0'/>"
        + "<path class='' d='M0 0'/></svg>"
    )
    assert_equal(plain.paths[1].style.fill, "#000")


def test_curves() raises:
    var line = SvgCurve(LINE, [SvgVector(0, 0), SvgVector(2, 4)])
    near(line.point(0.5)[1], 2)
    near(line.point(1)[0], 2)
    var quad = SvgCurve(
        QUADRATIC, [SvgVector(0, 0), SvgVector(1, 2), SvgVector(2, 0)]
    )
    near(quad.point(0.5)[1], 1)
    with assert_raises(contains="kind an outline does not use"):
        _ = SvgCurve(SPLINE, [SvgVector(0, 0), SvgVector(1, 1)]).point(0)
    with assert_raises(contains="kind an outline does not use"):
        _ = SvgCurve(CurveKind(9), [SvgVector(0, 0)]).point(0)
    with assert_raises(contains="do not match"):
        _ = SvgCurve(CUBIC, [SvgVector(0, 0)]).point(0)
    with assert_raises(contains="at least one division"):
        _ = line.get_points(0)
    # An ellipse: its angles the same, turned back, past a turn, and
    # clockwise through a whole turn.
    var dot = SvgCurve(SvgVector(1, 1), 2, 3, 1, 1, True, 0)
    near(dot.point(0.5)[0], 1 + 2 * 0.5403023058681398)
    var back = SvgCurve(SvgVector(0, 0), 1, 1, 0, -pi / 2, False, 0)
    near(back.point(1)[1], -1, 1e-9)
    var past = SvgCurve(SvgVector(0, 0), 1, 1, 0, 5 * pi, False, 0)
    near(past.point(1)[0], -1, 1e-9)
    var whole = SvgCurve(SvgVector(0, 0), 1, 1, 0, 2 * pi, True, 0)
    near(whole.point(0.25)[1], -1, 1e-9)
    var cw = SvgCurve(SvgVector(0, 0), 1, 1, 0, pi / 2, True, pi / 2)
    near(cw.point(1)[0], -1, 1e-9)
    near(js_remainder(-5, 2), -1)
    near(js_remainder(-4, 2), 0)
    near(js_remainder(5, 2), 1)


def test_sub_paths_and_conversion() raises:
    var sub = SvgSubPath()
    sub.move_to(0, 0)
    sub.line_to(0, 0)
    sub.line_to(4, 0)
    sub.quadratic_curve_to(4, 2, 4, 4)
    sub.abs_arc(2, 4, 2, 0, pi)
    sub.abs_ellipse(0, 2, 2, 2, pi / 2, pi, False, 0)
    sub.bezier_curve_to(0, 1, 1, 0, 0, 0)
    assert_equal(len(sub.curves), 7)
    var points = sub.get_points(2)
    near(points[0][0], 0)
    var path = sub.to_path()
    assert_equal(path.curve_count(), 6)
    # A path that does not end where it starts is closed by a line.
    var open = SvgSubPath()
    open.line_to(1, 0)
    open.line_to(1, 1)
    assert_equal(open.to_path().curve_count(), 3)
    var empty = SvgSubPath()
    empty.line_to(0, 0)
    with assert_raises(contains="nothing drawn"):
        _ = empty.to_path()
    with assert_raises(contains="nothing drawn"):
        _ = SvgSubPath().to_path()
    var nothing = SvgShapePath()
    transform_path(nothing, SvgMatrix())
    nothing.sub_paths.append(SvgSubPath())
    transform_path(nothing, SvgMatrix())
    assert_equal(len(nothing.sub_paths[0].curves), 0)
    var odd = SvgSubPath()
    odd.curves.append(SvgCurve(SPLINE, [SvgVector(0, 0), SvgVector(1, 1)]))
    with assert_raises(contains="does not use"):
        _ = odd.to_path()
    # A closed outline of one point stays one point.
    var one = SvgSubPath()
    one.auto_close = True
    one.line_to(0, 0)
    assert_equal(len(one.get_points()), 1)
    var shape_path = SvgShapePath()
    with assert_raises(contains="draws before it moves"):
        shape_path.line_to(1, 1)
    with assert_raises(contains="draws before it moves"):
        shape_path.quadratic_curve_to(1, 1, 2, 2)
    with assert_raises(contains="draws before it moves"):
        shape_path.bezier_curve_to(1, 1, 2, 2, 3, 3)
    with assert_raises(contains="does not use"):
        transform_path_with_bad_curve()


def transform_path_with_bad_curve() raises:
    """Transform a shape path that holds a curve of a wrong kind."""
    var shape_path = SvgShapePath()
    shape_path.move_to(0, 0)
    shape_path.sub_paths[0].curves.append(
        SvgCurve(SPLINE, [SvgVector(0, 0), SvgVector(1, 1)])
    )
    transform_path(shape_path, SvgMatrix())


def test_matrices() raises:
    var m = SvgMatrix(2, 0, 1, 0, 4, 2, 0, 0, 1)
    var inv = m.inverse()
    var back = inv.apply_point(m.apply_point(SvgVector(3, 5)))
    near(back[0], 3)
    near(back[1], 5)
    var zero = SvgMatrix(1, 2, 0, 2, 4, 0, 0, 0, 0).inverse()
    near(zero.e[0], 0)
    var t = SvgMatrix(1, 2, 3, 4, 5, 6, 7, 8, 9).transposed()
    near(t.e[1], 2)
    assert_true(is_transform_flipped(SvgMatrix(-1, 0, 0, 0, 1, 0, 0, 0, 1)))
    assert_false(is_transform_flipped(SvgMatrix()))
    assert_false(is_transform_skewed(SvgMatrix()))
    assert_true(is_transform_skewed(SvgMatrix(1, 1, 0, 0, 1, 0, 0, 0, 1)))
    assert_false(is_transform_skewed(SvgMatrix(1, 1e-20, 0, 0, 1, 0, 0, 0, 1)))


def test_eigen_decomposition() raises:
    var a = eigen_decomposition(3, 1, 2)
    near(a.rt1, 3.618033988749895)
    near(a.rt2, 1.381966011250105)
    var b = eigen_decomposition(-3, 1, -2)
    assert_true(isnan(b.rt1))
    near(b.rt2, -3.618033988749895)
    var c = eigen_decomposition(1, 0, -1)
    near(c.rt1, 1)
    near(c.rt2, -1)
    near(c.cs, -1)
    var d = eigen_decomposition(1, 0, 1)
    near(d.cs, 1)
    near(d.sn, 0)
    var e = eigen_decomposition(1, 5, 1)
    near(e.rt1, 6)
    var f = eigen_decomposition(2, 5, 1)
    near(f.rt2, 1.5 - sqrt_of(1 + 100) / 2)


def sqrt_of(x: Float64) -> Float64:
    """Return a square root."""
    from std.math import sqrt

    return sqrt(x)


def test_transform_ellipses() raises:
    # A skew reshapes an arc and a full ellipse; a mirror turns an arc's
    # direction; a scale of zero on x keeps the rotation from y.
    var path = SvgShapePath()
    var sub = SvgSubPath()
    sub.abs_ellipse(0, 0, 2, 1, 0, pi / 2, False, 0.25)
    sub.abs_ellipse(5, 0, 2, 1, 0, 2 * pi, False, 0)
    sub.abs_ellipse(9, 0, 2, 1, 1, 0, False, 0)
    path.sub_paths.append(sub^)
    var skewed = path.copy()
    transform_path(skewed, SvgMatrix(1, 0.5, 0, 0, -1, 0, 0, 0, 1))
    ref curves = skewed.sub_paths[0].curves
    assert_true(curves[0].clockwise)
    near(curves[3].start_angle, 0)
    var flipped = path.copy()
    transform_path(flipped, SvgMatrix(-1, 0, 0, 0, 1, 0, 0, 0, 1))
    assert_true(flipped.sub_paths[0].curves[0].clockwise)
    near(flipped.sub_paths[0].curves[0].end_angle, -pi / 2)
    var squashed = path.copy()
    transform_path(squashed, SvgMatrix(0, 0, 0, 0, 2, 0, 0, 0, 1))
    near(squashed.sub_paths[0].curves[0].x_radius, 0)
    near(squashed.sub_paths[0].curves[0].rotation, 0.25)


def test_fill_rules_and_names() raises:
    assert_true(svg_fill_rule("") == SVG_NONZERO)
    assert_true(svg_fill_rule("nonzero") == SVG_NONZERO)
    assert_true(svg_fill_rule("evenodd") == SVG_EVENODD)
    with assert_raises(contains="not implemented"):
        _ = svg_fill_rule("inherit")
    assert_false(SvgFillRule(2).is_valid())
    assert_false(SvgFillRule(-1).is_valid())
    assert_true(svg_line_join("bevel") == SVG_JOIN_BEVEL)
    assert_true(svg_line_join("round") == SVG_JOIN_ROUND)
    assert_true(svg_line_join("miter-clip") == SVG_JOIN_MITER_CLIP)
    assert_true(svg_line_join("arcs") == SVG_JOIN_MITER)
    assert_true(svg_line_cap("round") == SVG_CAP_ROUND)
    assert_true(svg_line_cap("square") == SVG_CAP_SQUARE)
    assert_true(svg_line_cap("x") == SVG_CAP_BUTT)
    assert_false(SvgLineJoin(4).is_valid())
    assert_false(SvgLineJoin(-1).is_valid())
    assert_false(SvgLineCap(3).is_valid())
    assert_false(SvgLineCap(-1).is_valid())
    var style = SvgStrokeStyle(SvgStyle())
    assert_true(style.join == SVG_JOIN_MITER)
    assert_true(style.cap == SVG_CAP_BUTT)


def square(x: Float64, y: Float64, size: Float64, cw: Bool) -> SvgSubPath:
    """Return a square outline, clockwise or not."""
    var sub = SvgSubPath()
    sub.move_to(x, y)
    if cw:
        sub.line_to(x, y + size)
        sub.line_to(x + size, y + size)
        sub.line_to(x + size, y)
    else:
        sub.line_to(x + size, y)
        sub.line_to(x + size, y + size)
        sub.line_to(x, y + size)
    sub.auto_close = True
    return sub^


def test_create_shapes() raises:
    # Nested squares that alternate direction, one beside them, and one
    # with a single point.
    var path = SvgShapePath()
    path.sub_paths.append(square(0, 0, 10, False))
    path.sub_paths.append(square(2, 2, 6, True))
    path.sub_paths.append(square(3, 3, 4, True))
    path.sub_paths.append(square(20, 0, 5, False))
    var dot = SvgSubPath()
    dot.move_to(1, 1)
    path.sub_paths.append(dot^)
    # three.js 0.180 gives three shapes by either rule, the first with one
    # hole.
    var nonzero = create_shapes_with_rule(path, SVG_NONZERO)
    assert_equal(len(nonzero), 3)
    assert_equal(len(nonzero[0].holes), 1)
    assert_equal(len(nonzero[1].holes), 0)
    var evenodd = create_shapes_with_rule(path, SVG_EVENODD)
    assert_equal(len(evenodd), 3)
    assert_equal(len(evenodd[0].holes), 1)
    assert_equal(len(evenodd[1].holes), 0)

    with assert_raises(contains="fill rule that is not valid"):
        _ = create_shapes_with_rule(path, SvgFillRule(5))
    path.style.fill_rule = "inherit"
    with assert_raises(contains="not implemented"):
        _ = create_shapes(path)
    var shape = nonzero[0].to_shape()
    assert_equal(shape.hole_count(), 1)
    assert_equal(nonzero[1].to_shape().hole_count(), 0)
    near(shape_area(List[SvgVector]()), 0)
    # An outline with a coordinate that is not a number: the scan line
    # never crosses it, and three.js throws a `TypeError`.
    var flat = SvgShapePath()
    var line = SvgSubPath()
    line.move_to(0, 0)
    line.line_to(nan[DType.float64](), 0)
    flat.sub_paths.append(line^)
    with assert_raises(contains="does not cross"):
        _ = create_shapes(flat)
    assert_equal(len(create_shapes(SvgShapePath())), 0)
    # A U: the scan line through the square in its notch crosses the U
    # twice before it, so the square is not a hole.
    var u = SvgShapePath()
    var outline = SvgSubPath()
    outline.move_to(0, 0)
    outline.line_to(30, 0)
    outline.line_to(30, 30)
    outline.line_to(20, 30)
    outline.line_to(20, 10)
    outline.line_to(10, 10)
    outline.line_to(10, 30)
    outline.line_to(0, 30)
    outline.auto_close = True
    u.sub_paths.append(outline^)
    u.sub_paths.append(square(12, 20, 6, False))
    assert_equal(len(create_shapes(u)), 2)
    # Two squares that run the same way: nonzero fills both as one.
    var same = SvgShapePath()
    same.sub_paths.append(square(0, 0, 10, False))
    same.sub_paths.append(square(2, 2, 6, False))
    assert_equal(len(create_shapes(same)), 2)
    near(shape_area([SvgVector(0, 0), SvgVector(1, 0), SvgVector(0, 1)]), 0.5)


def check_hit(
    got: Optional[SIMD[DType.float64, 4]], x: Float64, y: Float64, t: Float64
) raises:
    """Assert an intersection."""
    assert_true(Bool(got))
    var hit = got.value()
    near(hit[0], x)
    near(hit[1], y)
    near(hit[2], t)


def test_edge_intersections() raises:
    var a0 = SvgVector(0, 0)
    var a1 = SvgVector(10, 0)
    # Parallel apart, crossing, and ending on the first edge.
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(0, 1), SvgVector(5, 1)))
    )
    check_hit(
        find_edge_intersection(a0, a1, SvgVector(5, -1), SvgVector(5, 1)),
        5,
        0,
        0.5,
    )
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(0, 0), SvgVector(0, 3)))
    )
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(10, 0), SvgVector(10, 3)))
    )
    # In line: from the origin, in between, and past the end.
    check_hit(
        find_edge_intersection(a0, a1, SvgVector(0, 0), SvgVector(-5, 0)),
        0,
        0,
        0,
    )
    check_hit(
        find_edge_intersection(a0, a1, SvgVector(-2, 0), SvgVector(4, 0)),
        4,
        0,
        0.4,
    )
    check_hit(
        find_edge_intersection(
            SvgVector(0, 0), SvgVector(0, 10), SvgVector(0, 5), SvgVector(0, 20)
        ),
        0,
        5,
        0.5,
    )
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(12, 0), SvgVector(20, 0)))
    )
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(10, 0), SvgVector(20, 0)))
    )
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(-1, 0), SvgVector(-9, 0)))
    )
    near(to_precision_10(0), 0)
    assert_true(to_precision_10(inf[DType.float64]()) > 1e308)
    assert_true(isnan(to_precision_10(nan[DType.float64]())))
    near(to_precision_10(1234567890.4), 1234567890)
    near(to_precision_10(123456789012.6), 123456789000)
    # Where three.js next returns an end on the first edge's start, `t1`
    # is zero and the edges are refused.
    assert_false(
        Bool(find_edge_intersection(a0, a1, SvgVector(5, 5), SvgVector(0, 0)))
    )
    var o = SvgVector(0, 0)
    var e = SvgVector(10, 0)
    assert_true(classify_point(o, o, e)[0] == LOCATION_ORIGIN)
    assert_true(classify_point(e, o, e)[0] == LOCATION_DESTINATION)
    assert_true(classify_point(SvgVector(5, -1), o, e)[0] == LOCATION_LEFT)
    assert_true(classify_point(SvgVector(5, 1), o, e)[0] == LOCATION_RIGHT)
    assert_true(classify_point(SvgVector(-5, 0), o, e)[0] == LOCATION_BEHIND)
    assert_true(
        classify_point(SvgVector(0, -5), o, SvgVector(0, 10))[0]
        == LOCATION_BEHIND
    )
    assert_true(classify_point(SvgVector(15, 0), o, e)[0] == LOCATION_BEYOND)
    var between = classify_point(SvgVector(0, 4), o, SvgVector(0, 10))
    assert_true(between[0] == LOCATION_BETWEEN)
    near(between[1], 0.4)
    assert_true(LOCATION_BEYOND.is_valid())
    assert_false(PointLocation(7).is_valid())
    assert_false(PointLocation(-1).is_valid())
    near(to_precision_10(-1.23456789012345), -1.23456789)
    near(to_precision_10(9.9999999999), 10)
    near(to_precision_10(1.00000000004e-5), 1e-5)


def test_stroke_edges() raises:
    var style = SvgStrokeStyle()
    assert_equal(points_to_stroke([SvgVector(1, 1)], style).count, 0)
    with assert_raises(contains="no triangles"):
        _ = points_to_stroke([SvgVector(1, 1)], style).to_geometry()
    var stroke = points_to_stroke([SvgVector(0, 0), SvgVector(1, 0)], style)
    var geometry = stroke.to_geometry()
    assert_equal(geometry.vertex_count(), 6)
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_true(geometry.has_attribute(String(UV)))
    with assert_raises(contains="join or cap"):
        _ = points_to_stroke(
            [SvgVector(0, 0)], SvgStrokeStyle(1, SvgLineJoin(7), SVG_CAP_BUTT)
        )
    with assert_raises(contains="join or cap"):
        _ = points_to_stroke(
            [SvgVector(0, 0)], SvgStrokeStyle(1, SVG_JOIN_MITER, SvgLineCap(7))
        )
    with assert_raises(contains="arc division"):
        _ = points_to_stroke([SvgVector(0, 0)], style, 0)
    var kept = remove_duplicated_points(
        [
            SvgVector(0, 0),
            SvgVector(1, 0),
            SvgVector(1, 0.0001),
            SvgVector(2, 0),
        ],
        0.001,
    )
    assert_equal(len(kept), 3)
    # One division: a round cap is a single triangle.
    var round = points_to_stroke(
        [SvgVector(0, 0), SvgVector(1, 0)],
        SvgStrokeStyle(1, SVG_JOIN_ROUND, SVG_CAP_ROUND),
        1,
    )
    assert_equal(round.count, 36)
    # Two equal points: the normal of no length stays zero.
    var dot = points_to_stroke([SvgVector(2, 2), SvgVector(2, 2)], style)
    assert_equal(dot.count, 18)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
