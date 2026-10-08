# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Ideal monotonicity retains complete-cell scalar error and global charges."""

from extensions.carla.curve_bounds import _lane_jet
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import LINE, ARC, SPIRAL, POLY3, PARAM_POLY3
from extensions.carla.junction_bounds import (
    _monotone_coordinate,
    _monotone_coordinate_enclosure,
    _monotone_junction_enclosure,
    _certify_junction_span,
)
from extensions.carla.lane_value_bounds import _lane_value_bound
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoElevation
from math.bounds import Box3
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)
from tests.test_carla_lane_orientation import _road


def _same(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(
        bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high)
    )


def test_complete_cell_error_survives_both_monotone_directions() raises:
    # f(s)=s or 1-s on [0,1], with |stored(s)-f(s)|<=1/4. Endpoint scalar
    # evaluations may have zero error while an interior evaluation has 1/4.
    # No assumption about monotonicity of stored(s) is permissible.
    var original = _Interval(-4.0, 4.0)
    for derivative in [
        _Interval(1.0, 2.0),
        _Interval(-2.0, -1.0),
    ]:
        var whole = _Jet(original, derivative, _Interval.whole(), 0.25)
        var first = 0.0 if derivative.low > 0.0 else 1.0
        var last = 1.0 - first
        var bounded = _monotone_coordinate_enclosure(
            whole, _Interval.point(first), _Interval.point(last), original
        )
        assert_true(bounded.contains(-0.25))
        assert_true(bounded.contains(1.25))
        assert_true(bounded.low >= -0.250000000000001)
        assert_true(bounded.high <= 1.250000000000001)
    var constant = _Jet(original, _Interval(-0.0, 0.0), _Interval.whole(), 0.25)
    var constant_bound = _monotone_coordinate_enclosure(
        constant, _Interval.point(0.5), _Interval.point(0.5), original
    )
    assert_true(constant_bound.contains(0.25))
    assert_true(constant_bound.contains(0.75))
    assert_true(constant_bound.width() < 0.500000000000001)
    # A valid existing enclosure can be tighter than the endpoint proof.
    var whole = _Jet(original, _Interval.point(1), _Interval.whole(), 0.25)
    _same(
        _monotone_coordinate_enclosure(
            whole, _Interval.point(0), _Interval.point(1), _Interval(0.0, 1.0)
        ),
        _Interval(0.0, 1.0),
    )


def test_uncertainty_and_nonfinite_candidates_keep_original_enclosure() raises:
    var original = _Interval(-4.0, 4.0)
    for derivative in [_Interval.whole(), _Interval(-1.0, 1.0)]:
        var whole = _Jet(original, derivative, _Interval.whole(), 0.25)
        assert_false(_monotone_coordinate(whole))
        _same(
            _monotone_coordinate_enclosure(
                whole, _Interval.point(0), _Interval.point(1), original
            ),
            original,
        )
    for error in [-1.0, inf[DType.float64]()]:
        var whole = _Jet(original, _Interval.point(1), _Interval.whole(), error)
        _same(
            _monotone_coordinate_enclosure(
                whole, _Interval.point(0), _Interval.point(1), original
            ),
            original,
        )
    var whole = _Jet(original, _Interval.point(1), _Interval.whole(), 0.25)
    _same(
        _monotone_coordinate_enclosure(
            whole, _Interval.whole(), _Interval.point(1), original
        ),
        original,
    )
    _same(
        _monotone_coordinate_enclosure(
            whole, _Interval.point(1), _Interval.whole(), original
        ),
        original,
    )
    _same(
        _monotone_coordinate_enclosure(
            whole, _Interval.point(10), _Interval.point(11), original
        ),
        original,
    )
    whole.error = 1e308
    _same(
        _monotone_coordinate_enclosure(
            whole, _Interval.point(1e308), _Interval.point(1e308), original
        ),
        original,
    )


def test_exact_quadratic_extrema_and_full_error_cover_off_grid_values() raises:
    var road = _road(LINE)
    # f(s)=(s-1)^2+1 decreases on [1/2,7/8]. Its exact endpoint range
    # [65/64,5/4] follows from the square, independently of interval code.
    road.info.elevations[0].polynomial = CubicPolynomial(2, -2, 1, 0, 0)
    var point = _lane_jet(road, 0, 0, 0.5, 0.875)
    var first = _lane_value_bound(road, 0, 0, 0.5, 0.5)
    var last = _lane_value_bound(road, 0, 0, 0.875, 0.875)
    assert_true(_monotone_coordinate(point[2]))
    var original = point[2].rounded_value()
    var bound = _monotone_coordinate_enclosure(
        point[2], first[2].value, last[2].value, original
    )
    assert_true(original.width() > 3.0 * bound.width())
    assert_true(bound.contains(1.015625))
    assert_true(bound.contains(1.25))
    for i in range(258):
        var s = 0.5 + 0.375 * (Float64(i) + 0.317) / 258.0
        var expected = (s - 1.0) * (s - 1.0) + 1.0
        assert_true(bound.contains(expected))
        assert_true(bound.contains(road._lane_center(0, 0, s)[2]))


def test_optional_full_and_endpoint_graphs_are_reserved_before_evaluation() raises:
    var road = _road(LINE)
    road.info.elevations[0].polynomial = CubicPolynomial(2, -2, 1, 0, 0)
    var point = _lane_value_bound(road, 0, 0, 0.5, 0.875)
    var box = Box3(Vector3(-100, -100, 0.99), Vector3(100, 100, 1.26))
    var work = _MapBuildWork(MapBuildBudget())
    var bounds = _monotone_junction_enclosure(
        road,
        0,
        0,
        0.5,
        0.875,
        1,
        box,
        point[0].rounded_value(),
        -point[1].rounded_value(),
        point[2].rounded_value(),
        work,
    )
    assert_equal(work.terms, 3)
    assert_equal(work.steps, 33)
    assert_true(bounds[2].low >= 0.99)
    assert_true(bounds[2].high <= 1.26)
    var exact = _MapBuildWork(MapBuildBudget(0, work.steps, work.terms, 0))
    _ = _monotone_junction_enclosure(
        road,
        0,
        0,
        0.5,
        0.875,
        1,
        box,
        point[0].rounded_value(),
        -point[1].rounded_value(),
        point[2].rounded_value(),
        exact,
    )
    assert_equal(exact.steps, work.steps)
    assert_equal(exact.terms, work.terms)
    var terms = _MapBuildWork(MapBuildBudget(0, work.steps, work.terms - 1, 0))
    with assert_raises(contains="global term budget"):
        _ = _monotone_junction_enclosure(
            road,
            0,
            0,
            0.5,
            0.875,
            1,
            box,
            point[0].rounded_value(),
            -point[1].rounded_value(),
            point[2].rounded_value(),
            terms,
        )
    assert_equal(terms.terms, 2)
    assert_true(terms.exhausted)
    var steps = _MapBuildWork(MapBuildBudget(0, work.steps - 1, work.terms, 0))
    with assert_raises(contains="global step budget"):
        _ = _monotone_junction_enclosure(
            road,
            0,
            0,
            0.5,
            0.875,
            1,
            box,
            point[0].rounded_value(),
            -point[1].rounded_value(),
            point[2].rounded_value(),
            steps,
        )
    assert_true(steps.exhausted)
    var known = _MapBuildWork(MapBuildBudget())
    var broad = Box3(Vector3(-100, -100, -100), Vector3(100, 100, 100))
    _ = _monotone_junction_enclosure(
        road,
        0,
        0,
        0.5,
        0.875,
        1,
        broad,
        point[0].rounded_value(),
        -point[1].rounded_value(),
        point[2].rounded_value(),
        known,
    )
    assert_equal(known.terms, 1)
    assert_equal(known.steps, 11)


def test_integrated_certificate_retains_box_and_exact_budget_boundary() raises:
    var road = _road(LINE)
    road.info.elevations[0].polynomial = CubicPolynomial(2, -2, 1, 0, 0)
    var box = Box3(Vector3(-100, -100, 0.99), Vector3(100, 100, 1.26))
    var expected = box
    var work = _MapBuildWork(MapBuildBudget())
    _certify_junction_span(road, 0, 0, 0.5, 0.875, box, work)
    assert_true(box.min == expected.min)
    assert_true(box.max == expected.max)
    assert_equal(work.terms, 4)
    assert_equal(work.steps, 45)
    var exact = _MapBuildWork(MapBuildBudget(0, work.steps, work.terms, 0))
    _certify_junction_span(road, 0, 0, 0.5, 0.875, box, exact)
    var refused = _MapBuildWork(
        MapBuildBudget(0, work.steps, work.terms - 1, 0)
    )
    with assert_raises(contains="global term budget"):
        _certify_junction_span(road, 0, 0, 0.5, 0.875, box, refused)
    assert_true(refused.exhausted)


def test_record_clamp_and_trig_joins_do_not_assert_monotonicity() raises:
    var line = _road(LINE)
    line.info.elevations.append(
        RoadInfoElevation(0.75, CubicPolynomial.constant(12))
    )
    var joined = _lane_jet(line, 0, 0, 0.5, 1.0)
    assert_false(_monotone_coordinate(joined[0]))
    assert_false(_monotone_coordinate(joined[1]))
    assert_false(_monotone_coordinate(joined[2]))
    var clamped = _road(LINE)
    var tail = _lane_jet(clamped, 0, 0, 19.0, 21.0)
    assert_false(_monotone_coordinate(tail[0]))
    assert_false(_monotone_coordinate(tail[1]))
    for kind in [ARC, SPIRAL, POLY3, PARAM_POLY3]:
        var road = _road(kind)
        var whole = _lane_jet(road, 0, 0, 0.0, 20.0)
        assert_false(_monotone_coordinate(whole[0]))
        assert_false(_monotone_coordinate(whole[1]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
