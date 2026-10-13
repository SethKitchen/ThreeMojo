# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent local-coordinate cubic and certified-enclosure controls.

CARLA 1360bb9 expands record coefficients about the global road origin.
The cubic 3.5 + (x - 1000000)^3 is a reproducible cancellation control:
its value at the record origin is exactly 3.5, and its slope is zero.
These controls state the local polynomial directly, without reconstructing
expected answers with the production coefficient conversion.
"""

from extensions.carla.curve_bounds import _polynomial_jet
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_rounded_arc import (
    _rounded_constant,
    _rounded_arc_context,
)
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.geometry import LINE, ARC, RoadGeometry, with_arc
from extensions.carla.junction_bounds import (
    _polynomial_bounds,
    _centered_elevation_enclosure,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    RoadId,
    SectionId,
    LaneId,
    NO_JUNCTION,
    LANE_DRIVING,
    RoadInfoGeometry,
    RoadInfoElevation,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
)
from std.math import inf, nan, isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from units.si import Length64, Angle64, InverseLength64, InverseArea64


def _bad_values() -> List[Float64]:
    return [nan[DType.float64](), inf[DType.float64](), -inf[DType.float64]()]


def _word(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _conditioned() raises -> CubicPolynomial:
    return CubicPolynomial(
        Length64(3.5),
        0,
        InverseLength64(0),
        InverseArea64(1),
        Length64(1000000),
    )


def _road(arc: Bool = False) raises -> Road:
    var road = Road(
        RoadId(1),
        "local",
        Length64(10),
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), Length64(0))
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(Length64(0), CubicPolynomial.constant(Length64(2)))
    )
    var geometry = RoadGeometry(
        LINE, Length64(0), Length64(0), Length64(0), Angle64(0), Length64(10)
    )
    if arc:
        geometry = with_arc(geometry^, InverseLength64(0.125))
    road.info.geometries.append(RoadInfoGeometry(Length64(0), geometry^))
    road.info.elevations.append(
        RoadInfoElevation(Length64(0), CubicPolynomial.constant(Length64(0)))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(Length64(0), CubicPolynomial.constant(Length64(0)))
    )
    return road^


def test_record_origin_and_neighbors_use_local_coefficients() raises:
    var p = _conditioned()
    assert_equal(p.a, 3.5)
    assert_equal(p.b, 0)
    assert_equal(p.c, 0)
    assert_equal(p.d, 1)
    assert_equal(p.s, 1000000)
    assert_equal(p.evaluate(Length64(1000000)).value, 3.5)
    assert_equal(p.evaluate_meters(1000000), 3.5)
    assert_equal(p.tangent(Length64(1000000)), 0)
    assert_equal(p.tangent_meters(1000000), 0)
    # The adjacent binary64 stations differ by exactly 2^-33 meters.
    var origin_word = _word(1000000.0)
    for word in [origin_word - UInt64(1), origin_word + UInt64(1)]:
        var station = bitcast[DType.float64](word)
        assert_equal(p.evaluate(Length64(station)).value, 3.5)
        assert_equal(p.tangent(Length64(station)), 4.0657581468206416e-20)
        var jet = _polynomial_jet(p, _Jet.variable(station, station))
        assert_true(jet.rounded_value().contains(3.5))
        assert_true(jet.first.contains(4.0657581468206416e-20))
    for shift in [-2.0, -1.0, 0.0, 1.0, 2.0]:
        # Integer shifts make both the independent cube and all derivatives exact.
        var expected = 3.5 + shift * shift * shift
        assert_equal(p.evaluate(Length64(1000000.0 + shift)).value, expected)
        assert_equal(
            p.tangent(Length64(1000000.0 + shift)), 3.0 * shift * shift
        )


def test_typed_coefficients_and_raw_views_keep_every_binary64_bit() raises:
    var q = bitcast[DType.float64](UInt64(0x3FF0000000000001))
    var p = CubicPolynomial(
        Length64(q), q, InverseLength64(q), InverseArea64(q), Length64(q)
    )
    var raw = CubicPolynomial.from_coefficients(q, q, q, q, q)
    assert_equal(_word(p.a_quantity().value), _word(q))
    assert_equal(_word(p.b), _word(q))
    assert_equal(_word(p.c_quantity().value), _word(q))
    assert_equal(_word(p.d_quantity().value), _word(q))
    assert_equal(_word(p.s_quantity().value), _word(q))
    assert_equal(_word(raw.a), _word(p.a))
    assert_equal(_word(raw.b), _word(p.b))
    assert_equal(_word(raw.c), _word(p.c))
    assert_equal(_word(raw.d), _word(p.d))
    assert_equal(_word(raw.s), _word(p.s))
    assert_equal(_word(p.evaluate(Length64(q)).value), _word(q))
    assert_equal(_word(p.tangent(Length64(q))), _word(q))
    assert_equal(_word(CubicPolynomial.constant(Length64(q)).a), _word(q))
    assert_equal(_word(CubicPolynomial.constant_si(q).a), _word(q))


def test_subnormal_local_coefficients_are_not_erased_by_translation() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var p = CubicPolynomial(
        Length64(eta),
        eta,
        InverseLength64(eta),
        InverseArea64(eta),
        Length64(1000000),
    )
    assert_equal(_word(p.evaluate(Length64(1000000)).value), UInt64(1))
    assert_equal(_word(p.tangent(Length64(1000000))), UInt64(1))
    assert_equal(_word(p.evaluate(Length64(1000001)).value), UInt64(4))
    assert_equal(_word(p.tangent(Length64(1000001))), UInt64(6))
    var jet = _polynomial_jet(p, _Jet.variable(1000000, 1000001))
    assert_true(jet.rounded_value().contains(eta))
    assert_true(jet.rounded_value().contains(4.0 * eta))
    assert_true(jet.first.contains(eta))
    assert_true(jet.first.contains(6.0 * eta))


def test_wide_local_interval_encloses_values_and_both_derivatives() raises:
    var p = _conditioned()
    var jet = _polynomial_jet(p, _Jet.variable(998976, 1001024))
    var bounds = _polynomial_bounds(p, 998976, 1001024)
    # Cubes of integer offsets in [-1024, 1024] are exact binary64 integers.
    for i in range(65):
        var offset = Float64(-1024 + 32 * i)
        var value = 3.5 + offset * offset * offset
        var first = 3.0 * offset * offset
        var second = 6.0 * offset
        assert_true(jet.value.contains(value))
        assert_true(jet.rounded_value().contains(value))
        assert_true(jet.first.contains(first))
        assert_true(jet.second.contains(second))
        assert_true(abs(value) <= bounds[0])
        assert_true(abs(first) <= bounds[1])
        assert_true(abs(second) <= bounds[2])
    assert_true(isfinite(bounds[0]))
    assert_true(isfinite(bounds[1]))
    assert_true(isfinite(bounds[2]))
    assert_true(isfinite(bounds[3]))
    assert_true(bounds[0] < 2e9)


def test_constant_junction_bound_has_exact_zero_derivatives() raises:
    var p = CubicPolynomial(
        Length64(3.5),
        0,
        InverseLength64(0),
        InverseArea64(0),
        Length64(1000000),
    )
    var bounds = _polynomial_bounds(p, 999999, 1000001)
    assert_true(bounds[0] >= 3.5)
    assert_equal(bounds[1], 0.0)
    assert_equal(bounds[2], 0.0)
    assert_true(isfinite(bounds[3]))
    var rounded = _rounded_constant(p)
    assert_true(rounded.known)
    assert_equal(rounded.low, 3.5)
    assert_equal(rounded.high, 3.5)


def test_overflowing_local_subtraction_refuses_instead_of_hiding_zero_terms() raises:
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var p = CubicPolynomial(
        Length64(3.5), 0, InverseLength64(0), InverseArea64(0), Length64(-limit)
    )
    with assert_raises(contains="finite"):
        _ = p.evaluate(Length64(limit))
    with assert_raises(contains="finite"):
        _ = p.evaluate_meters(limit)
    with assert_raises(contains="finite"):
        _ = p.tangent(Length64(limit))
    with assert_raises(contains="finite"):
        _ = p.tangent_meters(limit)
    assert_false(
        _polynomial_jet(p, _Jet.variable(limit, limit))
        .rounded_value()
        .is_finite()
    )
    assert_false(_rounded_constant(p).known)


def test_centered_elevation_uses_local_origin_and_intersects_original_bound() raises:
    var road = _road()
    road.info.elevations[0].polynomial = _conditioned()
    var p = _conditioned()
    var jet = _polynomial_jet(p, _Jet.variable(1000001, 1000002))
    var original = jet.rounded_value()
    var work = _MapBuildWork(MapBuildBudget())
    var centered = _centered_elevation_enclosure(
        road, 1000001, 1000002, original, jet.error, work
    )
    assert_true(centered.is_finite())
    assert_true(centered.low >= original.low)
    assert_true(centered.high <= original.high)
    for i in range(33):
        var offset = 1.0 + Float64(i) / 32.0
        var expected = 3.5 + offset * offset * offset
        assert_true(centered.contains(expected))
        assert_true(centered.contains(p.evaluate_meters(1000000.0 + offset)))
    # A caller's narrower valid enclosure remains an intersection, rather
    # than being discarded in favor of a reordered floating expression.
    var tight = _Interval(4.5, 11.5)
    var intersected = _centered_elevation_enclosure(
        road, 1000001, 1000002, tight, jet.error, work
    )
    assert_equal(intersected.low, 4.5)
    assert_equal(intersected.high, 11.5)


def test_nonfinite_stored_origin_declines_both_rounded_certificates() raises:
    for is_arc in [False, True]:
        var road = _road(is_arc)
        road.info.elevations[0].polynomial.s = 1000000
        if is_arc:
            assert_true(Bool(_rounded_arc_context(road, 0, 0, 1, 9)))
        else:
            assert_true(Bool(_rounded_line_axis_context(road, 0, 0, 1, 9)))
        for bad in _bad_values():
            road.info.elevations[0].polynomial.s = bad
            assert_false(
                _rounded_constant(road.info.elevations[0].polynomial).known
            )
            if is_arc:
                assert_false(Bool(_rounded_arc_context(road, 0, 0, 1, 9)))
            else:
                assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 1, 9)))
            with assert_raises(contains="finite"):
                _ = road.info.elevations[0].polynomial.evaluate(Length64(1))
            road.info.elevations[0].polynomial.s = 1000000


def test_every_coefficient_and_station_boundary_rejects_nonfinite_values() raises:
    for bad in _bad_values():
        for index in range(5):
            var fields = List[Float64](length=5, fill=0.0)
            fields[index] = bad
            with assert_raises(contains="finite"):
                _ = CubicPolynomial(
                    Length64(fields[0]),
                    fields[1],
                    InverseLength64(fields[2]),
                    InverseArea64(fields[3]),
                    Length64(fields[4]),
                )
            with assert_raises(contains="finite"):
                _ = CubicPolynomial.from_coefficients(
                    fields[0], fields[1], fields[2], fields[3], fields[4]
                )
        with assert_raises(contains="finite"):
            _ = CubicPolynomial.constant(Length64(bad))
        with assert_raises(contains="finite"):
            _ = CubicPolynomial.constant_si(bad)
        var p = _conditioned()
        with assert_raises(contains="finite"):
            _ = p.evaluate(Length64(bad))
        with assert_raises(contains="finite"):
            _ = p.tangent(Length64(bad))
        p.a = bad
        with assert_raises(contains="finite"):
            _ = p.a_quantity()
        with assert_raises(contains="finite"):
            _ = p.evaluate_meters(1000000)
        with assert_raises(contains="finite"):
            _ = p.tangent_meters(1000000)
        p = _conditioned()
        p.b = bad
        with assert_raises(contains="finite"):
            _ = p.evaluate_meters(1000000)
        with assert_raises(contains="finite"):
            _ = p.tangent_meters(1000000)
        p = _conditioned()
        p.c = bad
        with assert_raises(contains="finite"):
            _ = p.c_quantity()
        with assert_raises(contains="finite"):
            _ = p.evaluate_meters(1000000)
        with assert_raises(contains="finite"):
            _ = p.tangent_meters(1000000)
        p = _conditioned()
        p.d = bad
        with assert_raises(contains="finite"):
            _ = p.d_quantity()
        with assert_raises(contains="finite"):
            _ = p.evaluate_meters(1000000)
        with assert_raises(contains="finite"):
            _ = p.tangent_meters(1000000)
        p = _conditioned()
        p.s = bad
        with assert_raises(contains="finite"):
            _ = p.s_quantity()
        with assert_raises(contains="finite"):
            _ = p.evaluate_meters(1000000)
        with assert_raises(contains="finite"):
            _ = p.tangent_meters(1000000)


def test_coefficient_fields_preserve_signed_zero_subnormal_and_maximum_bits() raises:
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        # Do not evaluate the maximum coefficients: this checks the public
        # storage contract without creating an unrelated arithmetic overflow.
        var p = CubicPolynomial(
            Length64(value),
            value,
            InverseLength64(value),
            InverseArea64(value),
            Length64(value),
        )
        var raw = CubicPolynomial.from_coefficients(
            value, value, value, value, value
        )
        assert_equal(_word(p.a_quantity().value), word)
        assert_equal(_word(p.b), word)
        assert_equal(_word(p.c_quantity().value), word)
        assert_equal(_word(p.d_quantity().value), word)
        assert_equal(_word(p.s_quantity().value), word)
        assert_equal(_word(raw.a), word)
        assert_equal(_word(raw.b), word)
        assert_equal(_word(raw.c), word)
        assert_equal(_word(raw.d), word)
        assert_equal(_word(raw.s), word)


def test_rounded_constant_origin_guard_includes_exact_boundary_only() raises:
    var boundary_word = UInt64(1423) << UInt64(52)
    var boundary = bitcast[DType.float64](boundary_word)
    var outside = bitcast[DType.float64](boundary_word + UInt64(1))
    for origin in [boundary, -boundary]:
        var p = CubicPolynomial(
            Length64(3.5),
            0,
            InverseLength64(0),
            InverseArea64(0),
            Length64(origin),
        )
        var rounded = _rounded_constant(p)
        assert_true(rounded.known)
        assert_equal(rounded.low, 3.5)
        assert_equal(rounded.high, 3.5)
    for origin in [outside, -outside]:
        var p = CubicPolynomial(
            Length64(3.5),
            0,
            InverseLength64(0),
            InverseArea64(0),
            Length64(origin),
        )
        assert_false(_rounded_constant(p).known)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
