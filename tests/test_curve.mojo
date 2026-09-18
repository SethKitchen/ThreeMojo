# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.vector2`, `math.curve` and `math.path`."""

from math.curve import (
    ARC_DIVISIONS,
    CUBIC,
    Curve,
    CurveKind,
    LINE,
    QUADRATIC,
    SPLINE,
    cubic_bezier,
    line,
    quadratic_bezier,
    spline,
    u_to_t,
)
from math.path import Path, Shape
from math.vector2 import Vector2
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER

comptime TOLERANCE = Float64(1e-5)


def assert_point(got: Vector2, x: Float32, y: Float32) raises:
    """Assert a point lies at (x, y), within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)


# --- Vector2 ----------------------------------------------------------------


def test_vector2_arithmetic() raises:
    var a = Vector2(3, 4)
    var b = Vector2(1, 2)
    assert_point(a + b, 4, 6)
    assert_point(a - b, 2, 2)
    assert_point(a * 2, 6, 8)
    assert_point(-a, -3, -4)
    assert_equal(a.dot(b), Float32(11))
    assert_equal(a.length(), Float32(5))


def test_vector2_cross() raises:
    assert_equal(Vector2(1, 0).cross(Vector2(0, 1)), Float32(1))
    assert_equal(Vector2(0, 1).cross(Vector2(1, 0)), Float32(-1))
    assert_equal(Vector2(2, 2).cross(Vector2(1, 1)), Float32(0))


def test_vector2_mutating() raises:
    var a = Vector2(1, 2)
    a.add(Vector2(3, 4))
    assert_point(a, 4, 6)
    a.sub(Vector2(1, 1))
    assert_point(a, 3, 5)


def test_vector2_normalize() raises:
    var a = Vector2(0, 5)
    a.normalize()
    assert_point(a, 0, 1)
    # A zero vector has no direction to scale, and is left as it is.
    var zero = Vector2(0, 0)
    zero.normalize()
    assert_point(zero, 0, 0)


# --- CurveKind --------------------------------------------------------------


def test_curve_kind_is_valid() raises:
    assert_true(LINE.is_valid())
    assert_true(QUADRATIC.is_valid())
    assert_true(CUBIC.is_valid())
    assert_true(SPLINE.is_valid())
    assert_false(CurveKind(9).is_valid())


def test_curve_kind_control_count() raises:
    assert_equal(LINE.control_count(), 2)
    assert_equal(QUADRATIC.control_count(), 3)
    assert_equal(CUBIC.control_count(), 4)
    assert_equal(SPLINE.control_count(), 0)


def test_curve_refuses_a_kind_that_does_not_exist() raises:
    with assert_raises():
        _ = Curve(CurveKind(9), [Vector2(0, 0), Vector2(1, 0)])


def test_curve_refuses_the_wrong_number_of_points() raises:
    with assert_raises():
        _ = Curve(LINE, [Vector2(0, 0)])
    with assert_raises():
        _ = Curve(QUADRATIC, [Vector2(0, 0), Vector2(1, 0)])
    with assert_raises():
        _ = Curve(CUBIC, [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
    with assert_raises():
        _ = Curve(SPLINE, [Vector2(0, 0)])


def test_curve_refuses_points_that_are_all_the_same() raises:
    # Every point the same: neither component of any step differs.
    with assert_raises():
        _ = Curve(SPLINE, [Vector2(1, 1), Vector2(1, 1), Vector2(1, 1)])
    # One that differs only in y is still a curve.
    var upright = line(Vector2(0, 0), Vector2(0, 1))
    assert_point(upright.point(1), 0, 1)


# --- points along a curve ---------------------------------------------------


def test_line_point() raises:
    var run = line(Vector2(0, 0), Vector2(4, 2))
    assert_point(run.point(0), 0, 0)
    assert_point(run.point(0.5), 2, 1)
    assert_point(run.point(1), 4, 2)


def test_line_length_and_tangent() raises:
    var run = line(Vector2(0, 0), Vector2(3, 4))
    assert_almost_equal(run.length().to(METER), Float32(5), atol=TOLERANCE)
    assert_point(run.tangent(0.25), 0.6, 0.8)


def test_quadratic_point() raises:
    var arc = quadratic_bezier(Vector2(0, 0), Vector2(1, 2), Vector2(2, 0))
    assert_point(arc.point(0), 0, 0)
    # At the middle a quadratic sits half way to its control point.
    assert_point(arc.point(0.5), 1, 1)
    assert_point(arc.point(1), 2, 0)


def test_cubic_point() raises:
    var arc = cubic_bezier(
        Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
    )
    assert_point(arc.point(0), 0, 0)
    assert_point(arc.point(0.5), 0.5, 0.75)
    assert_point(arc.point(1), 1, 0)


def test_cubic_tangent_is_exact() raises:
    var arc = cubic_bezier(
        Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
    )
    # Symmetric about the middle, so the direction there is along +x.
    assert_point(arc.tangent(0.5), 1, 0)
    # At the ends a Bezier leaves along its own control arm.
    assert_point(arc.tangent(0), 0, 1)
    assert_point(arc.tangent(1), 0, -1)


def test_quadratic_tangent_is_exact() raises:
    var arc = quadratic_bezier(Vector2(0, 0), Vector2(1, 2), Vector2(2, 0))
    assert_point(arc.tangent(0.5), 1, 0)


def test_spline_tangent_is_exact() raises:
    var through = spline(
        [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0)]
    )
    # Four points on a straight run: the direction is that run, everywhere.
    assert_point(through.tangent(0), 1, 0)
    assert_point(through.tangent(0.5), 1, 0)
    assert_point(through.tangent(1), 1, 0)


def test_curve_has_no_direction_at_a_cusp() raises:
    # A quadratic that ends where it began runs out to its control point
    # and back. Half way along it stops and turns, and the derivative
    # there is zero rather than nearly zero.
    var folded = quadratic_bezier(Vector2(0, 0), Vector2(1, 0), Vector2(0, 0))
    with assert_raises():
        _ = folded.tangent(0.5)
    assert_point(folded.tangent(0.25), 1, 0)


def test_spline_passes_through_its_points() raises:
    var through = spline(
        [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0), Vector2(3, 1)]
    )
    assert_point(through.point(0), 0, 0)
    assert_point(through.point(1.0 / 3.0), 1, 1)
    assert_point(through.point(2.0 / 3.0), 2, 0)
    # The last segment: `t` of one lands on the final point rather than
    # running off the end of the list.
    assert_point(through.point(1), 3, 1)


def test_spline_of_two_points_is_the_run_between_them() raises:
    var through = spline([Vector2(0, 0), Vector2(2, 0)])
    assert_point(through.point(0.5), 1, 0)


def test_curve_refuses_a_parameter_off_the_curve() raises:
    var run = line(Vector2(0, 0), Vector2(1, 0))
    with assert_raises():
        _ = run.point(-0.001)
    with assert_raises():
        _ = run.point(1.001)
    with assert_raises():
        _ = run.tangent(-0.001)
    with assert_raises():
        _ = run.tangent(1.001)
    with assert_raises():
        _ = run.point_at(-0.001)
    with assert_raises():
        _ = run.point_at(1.001)


# --- sampling and arc length ------------------------------------------------


def test_sample_counts_and_spacing() raises:
    var run = line(Vector2(0, 0), Vector2(4, 0))
    var points = run.sample(4)
    assert_equal(len(points), 5)
    assert_point(points[1], 1, 0)
    with assert_raises():
        _ = run.sample(0)


def test_lengths_rise_from_zero() raises:
    var run = line(Vector2(0, 0), Vector2(4, 0))
    var table = run.lengths(4)
    assert_equal(len(table), 5)
    assert_equal(table[0], Float32(0))
    assert_almost_equal(table[4], Float32(4), atol=TOLERANCE)


def test_spaced_points_are_equally_far_apart() raises:
    # A quadratic crawls at one end and races at the other, so equal steps
    # in `t` are not equal distances and equal distances are not equal `t`.
    var arc = quadratic_bezier(Vector2(0, 0), Vector2(4, 0), Vector2(4, 4))
    var spaced = arc.spaced_points(8)
    assert_equal(len(spaced), 9)
    var whole = arc.length().to(METER)
    for index in range(1, 9):
        var step = (spaced[index] - spaced[index - 1]).length()
        assert_almost_equal(step, whole / 8, atol=Float64(0.02))
    with assert_raises():
        _ = arc.spaced_points(0)


def test_point_at_runs_by_distance() raises:
    var run = line(Vector2(0, 0), Vector2(10, 0))
    assert_point(run.point_at(0), 0, 0)
    assert_point(run.point_at(0.5), 5, 0)
    assert_point(run.point_at(1), 10, 0)


def test_u_to_t_places_a_distance_between_two_samples() raises:
    var table: List[Float32] = [0, 1, 2, 3, 4]
    assert_almost_equal(u_to_t(table, 0), Float32(0), atol=TOLERANCE)
    assert_almost_equal(u_to_t(table, 0.5), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(u_to_t(table, 1), Float32(1), atol=TOLERANCE)
    # Half way along the first of four equal runs.
    assert_almost_equal(u_to_t(table, 0.125), Float32(0.125), atol=TOLERANCE)


def test_u_to_t_holds_still_where_the_curve_does() raises:
    # Two samples at the same distance: the curve stands still there, and
    # there is no span to place the target within.
    var table: List[Float32] = [0, 0, 1, 2]
    assert_almost_equal(u_to_t(table, 0), Float32(0), atol=TOLERANCE)


def test_arc_divisions_is_three_js_own() raises:
    assert_equal(ARC_DIVISIONS, 200)


# --- Path -------------------------------------------------------------------


def test_path_draws_a_run_of_curves() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(2, 0))
    pen.quadratic_to(Vector2(3, 0), Vector2(3, 1))
    pen.cubic_to(Vector2(3, 2), Vector2(2, 3), Vector2(0, 3))
    assert_equal(pen.curve_count(), 3)
    assert_point(pen.current(), 0, 3)


def test_path_starts_with_the_pen_up() raises:
    var pen = Path()
    assert_point(pen.current(), 0, 0)
    assert_equal(pen.curve_count(), 0)
    with assert_raises():
        pen.line_to(Vector2(1, 0))
    with assert_raises():
        pen.quadratic_to(Vector2(1, 0), Vector2(2, 0))
    with assert_raises():
        pen.cubic_to(Vector2(1, 0), Vector2(2, 0), Vector2(3, 0))
    with assert_raises():
        pen.spline_thru([Vector2(1, 0)])
    pen.move_to(Vector2(1, 1))
    pen.line_to(Vector2(2, 1))
    assert_equal(pen.curve_count(), 1)


def test_path_refuses_to_move_once_it_has_drawn() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    with assert_raises():
        pen.move_to(Vector2(5, 5))


def test_path_spline_thru() raises:
    var pen = Path(Vector2(0, 0))
    pen.spline_thru([Vector2(1, 1), Vector2(2, 0)])
    assert_equal(pen.curve_count(), 1)
    assert_point(pen.current(), 2, 0)
    with assert_raises():
        pen.spline_thru(List[Vector2]())


def test_path_closes() raises:
    var pen = Path(Vector2(0, 0))
    assert_false(pen.is_closed())
    pen.line_to(Vector2(1, 0))
    pen.line_to(Vector2(1, 1))
    assert_false(pen.is_closed())
    pen.close_path()
    assert_true(pen.is_closed())
    assert_equal(pen.curve_count(), 3)
    # Closing again would be a run of no length.
    with assert_raises():
        pen.close_path()


def test_path_that_ends_above_its_start_is_not_closed() raises:
    # The x components agree and the y components do not, which is the
    # second half of the test alone.
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    pen.line_to(Vector2(0, 1))
    assert_false(pen.is_closed())


def test_empty_path_has_no_points_no_length_and_no_close() raises:
    var pen = Path()
    with assert_raises():
        _ = pen.sample(4)
    with assert_raises():
        _ = pen.length()
    with assert_raises():
        pen.close_path()


def test_path_sample_does_not_repeat_a_join() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    pen.line_to(Vector2(2, 0))
    var points = pen.sample(2)
    # Two curves, two runs each: five points, not six.
    assert_equal(len(points), 5)
    assert_point(points[0], 0, 0)
    assert_point(points[2], 1, 0)
    assert_point(points[4], 2, 0)


def test_path_length_adds_its_curves_up() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(3, 0))
    pen.line_to(Vector2(3, 4))
    assert_almost_equal(pen.length().to(METER), Float32(7), atol=TOLERANCE)


def test_path_copies() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    var twin = Path(copy=pen)
    pen.line_to(Vector2(2, 0))
    assert_equal(twin.curve_count(), 1)
    assert_equal(pen.curve_count(), 2)


def test_curve_copies() raises:
    var run = line(Vector2(0, 0), Vector2(1, 0))
    var twin = Curve(copy=run)
    assert_true(twin.kind == LINE)
    assert_point(twin.point(1), 1, 0)


# --- Shape ------------------------------------------------------------------


def square(side: Float32) raises -> Path:
    """Return a closed square of `side` meters with a corner at the origin."""
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(side, 0))
    pen.line_to(Vector2(side, side))
    pen.line_to(Vector2(0, side))
    pen.close_path()
    return pen^


def test_shape_holds_an_outline_and_holes() raises:
    var outer = Shape(square(4))
    assert_equal(outer.hole_count(), 0)
    var hole = Path(Vector2(1, 1))
    hole.line_to(Vector2(2, 1))
    hole.line_to(Vector2(2, 2))
    hole.close_path()
    outer.add_hole(hole^)
    assert_equal(outer.hole_count(), 1)
    var points = outer.outline_points(1)
    assert_equal(len(points), 5)
    assert_point(points[0], 0, 0)
    assert_point(points[4], 0, 0)
    assert_equal(len(outer.hole_points(0, 1)), 4)


def test_shape_refuses_an_open_outline_or_hole() raises:
    var open_path = Path(Vector2(0, 0))
    open_path.line_to(Vector2(1, 0))
    with assert_raises():
        _ = Shape(Path(copy=open_path))
    var outer = Shape(square(4))
    with assert_raises():
        outer.add_hole(Path(copy=open_path))


def test_shape_refuses_a_hole_that_is_not_there() raises:
    var outer = Shape(square(4))
    with assert_raises():
        _ = outer.hole_points(-1, 1)
    with assert_raises():
        _ = outer.hole_points(0, 1)


def test_shape_copies() raises:
    var outer = Shape(square(4))
    var twin = Shape(copy=outer)
    var hole = Path(Vector2(1, 1))
    hole.line_to(Vector2(2, 1))
    hole.line_to(Vector2(2, 2))
    hole.close_path()
    outer.add_hole(hole^)
    assert_equal(twin.hole_count(), 0)
    assert_equal(outer.hole_count(), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
