# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.shape_path` and `loaders.font`: loose outlines sorted
into shapes with holes, and a typeface.js font laid out as shapes.

The expected layouts of `assets/fonts/fixture.typeface.json` come from
three.js 0.180's `Font.generateShapes`.
"""

from loaders.font import (
    CUBIC_TO,
    LINE_TO,
    MOVE_TO,
    QUADRATIC_TO,
    Font,
    Glyph,
    OutlineStep,
    OutlineVerb,
    parse_font,
    parse_outline,
    read_font,
)
from math.path import Shape
from math.shape_path import (
    ShapePath,
    is_clockwise,
    is_point_inside_polygon,
    signed_area,
)
from math.vector2 import Vector2
from std.collections import Dict
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


def square(low: Float32, high: Float32, clockwise: Bool) -> List[Vector2]:
    """Return a square's corners, running either way."""
    if clockwise:
        return [
            Vector2(low, low),
            Vector2(low, high),
            Vector2(high, high),
            Vector2(high, low),
        ]
    return [
        Vector2(low, low),
        Vector2(high, low),
        Vector2(high, high),
        Vector2(low, high),
    ]


def draw(mut path: ShapePath, corners: List[Vector2]) raises:
    """Draw an open outline through `corners` on a new subpath."""
    path.move_to(corners[0])
    for index in range(1, len(corners)):
        path.line_to(corners[index])


def assert_point(point: Vector2, x: Float32, y: Float32) raises:
    """Assert a point is where it should be."""
    assert_almost_equal(point.x, x, atol=1e-4)
    assert_almost_equal(point.y, y, atol=1e-4)


# --- signed area and point in polygon ---------------------------------------


def test_the_signed_area_says_which_way_a_contour_runs() raises:
    assert_almost_equal(signed_area(square(0, 2, False)), 4)
    assert_almost_equal(signed_area(square(0, 2, True)), -4)
    assert_equal(signed_area(List[Vector2]()), 0)
    assert_true(is_clockwise(square(0, 2, True)))
    assert_false(is_clockwise(square(0, 2, False)))


def test_a_point_inside_a_polygon() raises:
    for clockwise in [False, True]:
        var box = square(0, 2, clockwise)
        assert_true(is_point_inside_polygon(Vector2(1, 1), box))
        assert_false(is_point_inside_polygon(Vector2(3, 1), box))
        assert_false(is_point_inside_polygon(Vector2(-1, 1), box))
        assert_false(is_point_inside_polygon(Vector2(1, -1), box))
        assert_false(is_point_inside_polygon(Vector2(1, 3), box))


def test_a_point_on_the_boundary_is_inside() raises:
    var box = square(0, 2, False)
    # At a corner, on a level edge, and on a climbing edge.
    assert_true(is_point_inside_polygon(Vector2(0, 0), box))
    assert_true(is_point_inside_polygon(Vector2(1, 0), box))
    assert_true(is_point_inside_polygon(Vector2(2, 1), box))
    # Level with the bottom edge, past its end.
    assert_false(is_point_inside_polygon(Vector2(5, 0), box))
    assert_false(is_point_inside_polygon(Vector2(1, 0), List[Vector2]()))


# --- shape paths ------------------------------------------------------------


def test_a_shape_path_must_move_before_it_draws() raises:
    var path = ShapePath()
    with assert_raises(contains="move before it draws"):
        path.line_to(Vector2(1, 0))
    with assert_raises(contains="move before it draws"):
        path.quadratic_curve_to(Vector2(1, 1), Vector2(2, 0))
    with assert_raises(contains="move before it draws"):
        path.bezier_curve_to(Vector2(1, 1), Vector2(2, 1), Vector2(3, 0))


def test_an_empty_shape_path_has_no_shapes() raises:
    assert_equal(len(ShapePath().to_shapes()), 0)


def test_one_outline_is_one_shape_and_is_closed() raises:
    var path = ShapePath()
    draw(path, square(0, 2, False))
    var copy = ShapePath(copy=path)
    assert_equal(copy.path_count(), 1)
    var shapes = copy.to_shapes()
    assert_equal(len(shapes), 1)
    assert_equal(shapes[0].hole_count(), 0)
    assert_true(shapes[0].outline.is_closed())
    assert_equal(shapes[0].outline.curve_count(), 4)


def test_an_outline_that_is_closed_is_not_closed_again() raises:
    var path = ShapePath()
    var corners = square(0, 2, True)
    corners.append(corners[0])
    draw(path, corners)
    var shapes = path.to_shapes()
    assert_equal(shapes[0].outline.curve_count(), 4)


def test_an_outline_that_draws_nothing_is_refused() raises:
    var path = ShapePath()
    path.move_to(Vector2(1, 1))
    with assert_raises():
        _ = path.to_shapes()
    draw(path, square(0, 2, True))
    with assert_raises():
        _ = path.to_shapes()


def test_a_clockwise_solid_takes_the_counterclockwise_hole_after_it() raises:
    var path = ShapePath()
    draw(path, square(0, 4, True))
    draw(path, square(1, 3, False))
    var shapes = path.to_shapes()
    assert_equal(len(shapes), 1)
    assert_equal(shapes[0].hole_count(), 1)
    assert_point(shapes[0].outline.first, 0, 0)
    assert_point(shapes[0].holes[0].first, 1, 1)
    assert_true(shapes[0].holes[0].is_closed())


def test_is_ccw_swaps_solids_and_holes() raises:
    var path = ShapePath()
    draw(path, square(0, 4, False))
    draw(path, square(1, 3, True))
    var shapes = path.to_shapes(is_ccw=True)
    assert_equal(len(shapes), 1)
    assert_equal(shapes[0].hole_count(), 1)
    assert_point(shapes[0].outline.first, 0, 0)


def test_only_holes_are_shapes_wound_the_other_way() raises:
    var path = ShapePath()
    draw(path, square(0, 1, False))
    draw(path, square(2, 3, False))
    var shapes = path.to_shapes()
    assert_equal(len(shapes), 2)
    assert_equal(shapes[0].hole_count(), 0)
    assert_equal(shapes[1].hole_count(), 0)
    assert_point(shapes[1].outline.first, 2, 2)


def test_holes_first_go_to_the_solid_after_them() raises:
    var path = ShapePath()
    draw(path, square(1, 3, False))
    draw(path, square(0, 4, True))
    draw(path, square(11, 13, False))
    draw(path, square(10, 14, True))
    # A hole after the last solid has no solid to go to. three.js drops it.
    draw(path, square(21, 23, False))
    var shapes = path.to_shapes()
    assert_equal(len(shapes), 2)
    assert_equal(shapes[0].hole_count(), 1)
    assert_point(shapes[0].holes[0].first, 1, 1)
    assert_equal(shapes[1].hole_count(), 1)
    assert_point(shapes[1].holes[0].first, 11, 11)


def test_a_hole_moves_to_the_solid_it_lies_in() raises:
    var path = ShapePath()
    draw(path, square(0, 4, True))
    draw(path, square(10, 14, True))
    draw(path, square(1, 3, False))
    draw(path, square(11, 13, False))
    var shapes = path.to_shapes()
    assert_equal(shapes[0].hole_count(), 1)
    assert_point(shapes[0].holes[0].first, 1, 1)
    assert_equal(shapes[1].hole_count(), 1)
    assert_point(shapes[1].holes[0].first, 11, 11)


def test_holes_in_place_do_not_move() raises:
    var path = ShapePath()
    draw(path, square(0, 4, True))
    draw(path, square(1, 3, False))
    draw(path, square(10, 14, True))
    draw(path, square(11, 13, False))
    # Inside no solid: it stays with the solid it was drawn after.
    draw(path, square(21, 23, False))
    var shapes = path.to_shapes()
    assert_equal(shapes[0].hole_count(), 1)
    assert_equal(shapes[1].hole_count(), 2)
    assert_point(shapes[1].holes[1].first, 21, 21)


def test_a_hole_inside_two_solids_moves_nothing() raises:
    var path = ShapePath()
    draw(path, square(0, 4, True))
    draw(path, square(2, 6, True))
    # Inside both: ambiguous, so the hole inside the first solid that was
    # drawn after the second stays with the second, and so does this one.
    draw(path, square(2.5, 3.5, False))
    var shapes = path.to_shapes()
    assert_equal(shapes[0].hole_count(), 0)
    assert_equal(shapes[1].hole_count(), 1)


# --- outlines and glyphs ----------------------------------------------------


def test_an_outline_verb_is_one_of_four() raises:
    assert_true(MOVE_TO.is_valid())
    assert_true(LINE_TO.is_valid())
    assert_true(QUADRATIC_TO.is_valid())
    assert_true(CUBIC_TO.is_valid())
    assert_false(OutlineVerb(4).is_valid())
    assert_false(OutlineVerb(-1).is_valid())
    assert_equal(MOVE_TO.point_count(), 1)
    assert_equal(LINE_TO.point_count(), 1)
    assert_equal(QUADRATIC_TO.point_count(), 2)
    assert_equal(CUBIC_TO.point_count(), 3)
    assert_equal(OutlineVerb(4).point_count(), 0)


def test_an_outline_step_checks_its_verb_and_numbers() raises:
    with assert_raises(contains="unknown command"):
        _ = OutlineStep(OutlineVerb(7), List[Float32]())
    with assert_raises(contains="wrong count"):
        _ = OutlineStep(LINE_TO, [Float32(1)])
    var step = OutlineStep(QUADRATIC_TO, [Float32(1), 2, 3, 4])
    var copy = OutlineStep(copy=step)
    assert_point(copy.point(0), 1, 2)
    assert_point(copy.point(1), 3, 4)


def test_an_outline_puts_the_end_point_last() raises:
    var steps = parse_outline("m 0 0 l 10 0 q 20 10 20 0 b 0 20 20 20 5 25 ")
    assert_equal(len(steps), 4)
    assert_true(steps[0].verb == MOVE_TO)
    assert_true(steps[1].verb == LINE_TO)
    assert_point(steps[1].point(0), 10, 0)
    assert_true(steps[2].verb == QUADRATIC_TO)
    assert_point(steps[2].point(0), 20, 0)
    assert_point(steps[2].point(1), 20, 10)
    assert_true(steps[3].verb == CUBIC_TO)
    assert_point(steps[3].point(0), 20, 20)
    assert_point(steps[3].point(1), 5, 25)
    assert_point(steps[3].point(2), 0, 20)
    assert_equal(len(parse_outline("")), 0)
    assert_equal(len(parse_outline("   ")), 0)


def test_a_bad_outline_is_refused() raises:
    with assert_raises(contains="unknown command 'y'"):
        _ = parse_outline("m 0 0 l 1 0 y")
    # `z`, which three.js's TTFLoader writes, is stepped over.
    assert_equal(len(parse_outline("m 0 0 l 1 0 l 0 1 z")), 3)
    with assert_raises(contains="too few numbers"):
        _ = parse_outline("m 0")
    with assert_raises(contains="'x' is not a number"):
        _ = parse_outline("m x 0")
    with assert_raises(contains="is not finite"):
        _ = parse_outline("m 1e39 0")


def test_a_glyph_checks_its_outline() raises:
    var move = OutlineStep(MOVE_TO, [Float32(0), 0])
    var line = OutlineStep(LINE_TO, [Float32(1), 0])
    with assert_raises(contains="advance is not finite"):
        _ = Glyph(Float32.MAX * 2, List[OutlineStep]())
    with assert_raises(contains="draws before it moves"):
        _ = Glyph(1, [line.copy()])
    with assert_raises(contains="moves and draws nothing"):
        _ = Glyph(1, [move.copy(), move.copy(), line.copy()])
    with assert_raises(contains="moves and draws nothing"):
        _ = Glyph(1, [move.copy(), line.copy(), move.copy()])
    var glyph = Glyph(1, [move.copy(), line.copy(), move.copy(), line.copy()])
    assert_equal(len(Glyph(copy=glyph).steps), 4)
    assert_equal(len(Glyph(2, List[OutlineStep]()).steps), 0)


# --- the font ---------------------------------------------------------------


def test_the_fixture_font_is_read() raises:
    var font = read_font(FIXTURE)
    assert_equal(font.family_name, "Fixture Sans")
    assert_equal(font.resolution, 1000)
    assert_equal(font.y_min, -100)
    assert_equal(font.y_max, 800)
    assert_equal(font.underline_thickness, 50)
    assert_equal(font.glyph_count(), 7)
    assert_true(font.has_glyph("O"))
    assert_false(font.has_glyph("é"))
    assert_equal(font.glyph("A").advance, 620)
    # three.js's fallback: a character with no glyph takes `?`'s.
    assert_equal(font.glyph("é").advance, 300)
    assert_equal(len(font.glyph(" ").steps), 0)


def test_a_missing_font_file_is_refused() raises:
    with assert_raises():
        _ = read_font("assets/fonts/no_such.typeface.json")


def test_the_line_height_is_three_js_s() raises:
    var font = read_font(FIXTURE)
    # (800 - -100 + 50) * 100 / 1000.
    assert_almost_equal(font.line_height(Length(100, METER)).to(METER), 95)


def test_text_is_laid_out_as_three_js_lays_it() raises:
    var font = read_font(FIXTURE)
    var shapes = font.generate_shapes("AO i8\nD?é", Length(100, METER))
    # three.js 0.180: shape count, hole counts and each outline's start.
    assert_equal(len(shapes), 9)
    var holes: List[Int] = [1, 1, 0, 0, 1, 1, 1, 0, 0]
    var xs: List[Float32] = [0, 97, 162, 167, 177, 177, 0, 44, 74]
    var ys: List[Float32] = [0, 65, 0, 65, 40, 0, -95, -95, -95]
    for index in range(9):
        assert_equal(shapes[index].hole_count(), holes[index])
        assert_point(shapes[index].outline.first, xs[index], ys[index])
        assert_true(shapes[index].outline.is_closed())
    # The "O" is four quadratic curves around a hole of four more.
    assert_equal(shapes[1].outline.curve_count(), 4)
    assert_point(shapes[1].holes[0].first, 97, 50)
    # The "8" draws both solids and then both holes; each hole moves to
    # the solid it lies in.
    assert_point(shapes[4].holes[0].first, 187, 50)
    assert_point(shapes[5].holes[0].first, 187, 10)
    # The "D" draws its hole first.
    assert_point(shapes[6].holes[0].first, 10, -85)


def test_a_space_moves_the_pen_and_draws_nothing() raises:
    var font = read_font(FIXTURE)
    assert_equal(len(font.generate_shapes("  \n ")), 0)
    assert_equal(len(font.generate_shapes("")), 0)
    var paths = font.generate_paths("? ?", Length(10, METER))
    assert_equal(len(paths), 3)
    assert_equal(paths[1].path_count(), 0)
    assert_point(paths[2].sub_paths[0].first, 5.5, 0)


def test_the_default_size_is_one_hundred() raises:
    var font = read_font(FIXTURE)
    var shapes = font.generate_shapes("?")
    assert_point(shapes[0].outline.curves[0].point(1), 10, 40)


def test_a_text_size_must_be_positive() raises:
    var font = read_font(FIXTURE)
    with assert_raises(contains="must be positive"):
        _ = font.generate_shapes("A", Length(0, METER))
    with assert_raises(contains="must be positive"):
        _ = font.generate_shapes("A", Length(-1, METER))
    with assert_raises(contains="must be positive"):
        _ = font.generate_shapes("A", Length(Float32.MAX * 2, METER))


def fallback_font(glyphs: String) raises -> Font:
    """Return a font with the given glyph table."""
    return parse_font(
        '{"resolution": 10, "boundingBox": {"yMin": 0, "yMax": 10},'
        + ' "underlineThickness": 1, "glyphs": '
        + glyphs
        + "}"
    )


def test_a_character_with_no_glyph_and_no_question_mark_is_refused() raises:
    var font = fallback_font('{"x": {"ha": 5}}')
    assert_equal(font.family_name, "")
    with assert_raises(contains="'y' does not exist"):
        _ = font.generate_shapes("xy", Length(1, METER))


def test_a_step_that_draws_nothing_is_skipped() raises:
    var font = fallback_font(
        '{"x": {"ha": 5, "o": "m 0 0 l 0 0 l 10 0 q 10 0 10 0 b 10 0 10 0 10 0'
        + ' l 10 10 l 10 10 m 20 0 l 30 0 q 30 10 40 5 b 20 10 25 10 25 5"}}'
    )
    var paths = font.generate_paths("x", Length(10, METER))
    assert_equal(paths[0].path_count(), 2)
    assert_equal(paths[0].sub_paths[0].curve_count(), 2)
    assert_equal(paths[0].sub_paths[1].curve_count(), 3)


def test_a_bad_font_is_refused() raises:
    var head = String('"resolution": 10, "underlineThickness": 1')
    var box = String('"boundingBox": {"yMin": 0, "yMax": 10}')
    var table = String('"glyphs": {}')
    with assert_raises(contains="must hold a JSON object"):
        _ = parse_font("[]")
    with assert_raises(contains="has no 'resolution'"):
        _ = parse_font('{"underlineThickness": 1, ' + box + ", " + table + "}")
    with assert_raises(contains="resolution must be positive"):
        _ = parse_font(
            '{"resolution": 0, "underlineThickness": 1, '
            + box
            + ", "
            + table
            + "}"
        )
    with assert_raises(contains="resolution must be positive"):
        _ = parse_font(
            '{"resolution": 1e39, "underlineThickness": 1, '
            + box
            + ", "
            + table
            + "}"
        )
    with assert_raises(contains="has no 'boundingBox'"):
        _ = parse_font("{" + head + ", " + table + "}")
    with assert_raises(contains="'boundingBox' must be an object"):
        _ = parse_font("{" + head + ', "boundingBox": 3, ' + table + "}")
    with assert_raises(contains="has no 'yMin'"):
        _ = parse_font(
            "{" + head + ', "boundingBox": {"yMax": 1}, ' + table + "}"
        )
    with assert_raises(contains="bounding box must be finite"):
        _ = parse_font(
            "{"
            + head
            + ', "boundingBox": {"yMin": -1e39, "yMax": 1}, '
            + table
            + "}"
        )
    with assert_raises(contains="bounding box must be finite"):
        _ = parse_font(
            "{"
            + head
            + ', "boundingBox": {"yMin": 0, "yMax": 1e39}, '
            + table
            + "}"
        )
    with assert_raises(contains="has no 'underlineThickness'"):
        _ = parse_font('{"resolution": 10, ' + box + ", " + table + "}")
    with assert_raises(contains="underline thickness must be finite"):
        _ = parse_font(
            '{"resolution": 10, "underlineThickness": 1e39, '
            + box
            + ", "
            + table
            + "}"
        )
    with assert_raises(contains="has no 'glyphs'"):
        _ = parse_font("{" + head + ", " + box + "}")
    with assert_raises(contains="expected a string"):
        _ = parse_font(
            '{"familyName": 3, ' + head + ", " + box + ", " + table + "}"
        )


def test_a_bad_glyph_is_refused_by_name() raises:
    with assert_raises(contains="glyph 'x' must be an object"):
        _ = fallback_font('{"x": 3}')
    with assert_raises(contains="glyph 'x' has no 'ha'"):
        _ = fallback_font('{"x": {"o": ""}}')
    with assert_raises(contains="glyph 'x': 'o' must be a string"):
        _ = fallback_font('{"x": {"ha": 1, "o": 3}}')
    with assert_raises(contains="glyph 'x': unknown command 'y'"):
        _ = fallback_font('{"x": {"ha": 1, "o": "y"}}')
    with assert_raises(contains="glyph 'x': an outline draws before it moves"):
        _ = fallback_font('{"x": {"ha": 1, "o": "l 1 1"}}')
    with assert_raises(contains="glyph 'x': its advance is not finite"):
        _ = fallback_font('{"x": {"ha": 1e39}}')
    with assert_raises(contains="'xy' is not one character"):
        _ = fallback_font('{"xy": {"ha": 1}}')


def test_a_font_built_by_hand_checks_its_parts() raises:
    var glyphs = Dict[String, Glyph]()
    glyphs["é"] = Glyph(1, List[OutlineStep]())
    var font = Font("Hand", 10, 0, 10, 1, glyphs^)
    assert_true(font.has_glyph("é"))
    assert_equal(
        Font("None", 10, 0, 10, 1, Dict[String, Glyph]()).glyph_count(), 0
    )
    var nan = Float32(0) / Float32(0)
    with assert_raises(contains="resolution must be positive"):
        _ = Font("Hand", nan, 0, 10, 1, Dict[String, Glyph]())
    with assert_raises(contains="resolution must be positive"):
        _ = Font("Hand", -1, 0, 10, 1, Dict[String, Glyph]())
    var empty = Dict[String, Glyph]()
    empty[""] = Glyph(1, List[OutlineStep]())
    with assert_raises(contains="is not one character"):
        _ = Font("Hand", 10, 0, 10, 1, empty^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
