# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Typed plan-view constructors and the refusals of geometry records.

Each test gives one record or query that a guard must refuse, or uses a
typed view that no other suite uses. The expected numbers come from hand
calculation.
"""

from extensions.carla.geometry import (
    ARC,
    ARC_LENGTH,
    LINE,
    SPIRAL,
    RoadGeometry,
    arc,
    line,
    param_poly3_from_coefficients,
    spiral,
    with_poly3_si,
    with_spiral_si,
)
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Angle, Angle64, InverseLength64, Length, Length64


def _line(length: Float64) raises -> RoadGeometry:
    return RoadGeometry.from_meters(LINE, 0.0, 0.0, 0.0, 0.0, length)


def _poly3() raises -> RoadGeometry:
    # A straight cubic v(u) = 0 over 2 m keeps several table samples.
    return with_poly3_si(_line(2.0), 0.0, 0.0, 0.0, 0.0)


def test_typed_line_arc_and_spiral_constructors() raises:
    var straight = line(
        Length64(1.0), Length64(2.0), Length64(3.0), Angle64(0.0), Length64(4.0)
    )
    assert_equal(straight.kind, LINE)
    assert_equal(straight.end_s_meters(), 5.0)
    var curve = arc(
        Length64(0.0),
        Length64(0.0),
        Length64(0.0),
        Angle64(0.0),
        Length64(1.0),
        InverseLength64(0.5),
    )
    assert_equal(curve.kind, ARC)
    assert_equal(curve.curvature_start, 0.5)
    var clothoid = spiral(
        Length64(0.0),
        Length64(0.0),
        Length64(0.0),
        Angle64(0.0),
        Length64(1.0),
        InverseLength64(0.0),
        InverseLength64(0.25),
    )
    assert_equal(clothoid.kind, SPIRAL)
    assert_equal(clothoid.curvature_end, 0.25)


def test_v_coefficients_read_the_raw_v_cubic() raises:
    var u = CubicPolynomial.from_coefficients(0.0, 1.0, 0.0, 0.0, 0.0)
    var v = CubicPolynomial.from_coefficients(0.5, 0.0, 0.25, 0.0, 0.0)
    var record = param_poly3_from_coefficients(
        Length(0.0),
        Length(0.0),
        Length(0.0),
        Angle(0.0),
        Length(1.0),
        u,
        v,
        ARC_LENGTH,
    )
    var coefficients = record.v_coefficients()
    assert_equal(coefficients[0], 0.5)
    assert_equal(coefficients[1], 0.0)
    assert_equal(coefficients[2], 0.25)
    assert_equal(coefficients[3], 0.0)
    assert_equal(coefficients[4], 0.0)


def test_typed_distance_to_a_line() raises:
    # A point 3 m along the line and 4 m to its left.
    var result = _line(10.0).distance_to(Vector3(3, 4, 0))
    assert_almost_equal(Float64(result[0].value), 3.0)
    assert_almost_equal(Float64(result[1].value), 4.0)


def test_query_work_limits_refuse() raises:
    with assert_raises(contains="work limit must be positive"):
        _ = _line(1.0).pos_at_meters(0.5, max_steps=0)
    with assert_raises(contains="sample work limit"):
        _ = _poly3().pos_at_meters(0.5, max_steps=1)


def test_spiral_query_work_limits_refuse() raises:
    # The work estimate is past the Int range before the step limit.
    var long = with_spiral_si(
        RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 0.0, 0.0, 1e19), 0.0, 0.0
    )
    with assert_raises(contains="spiral work limit"):
        _ = long.pos_at_meters(1e19)
    # A short spiral needs ten pieces, more than the limit of two.
    var short = with_spiral_si(
        RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 0.0, 0.0, 10.0), 0.0, 0.0
    )
    with assert_raises(contains="spiral work limit"):
        _ = short.pos_at_meters(10.0, max_steps=2)
    var lane = with_spiral_si(
        RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 0.0, 0.0, 1.0), 0.0, 0.0
    )
    lane.curvature_start = Float64(1) / Float64(0)
    with assert_raises(contains="spiral work limit"):
        _ = _lane_geometry_pos_at(lane, 1.0)
    var past = with_spiral_si(
        RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 0.0, 0.0, 1e19), 1000.0, 0.0
    )
    with assert_raises(contains="spiral work limit"):
        _ = _lane_geometry_pos_at(past, 1e19)
    with assert_raises(contains="spiral work limit"):
        _ = _lane_geometry_pos_at(long, 1e19)


def test_poly3_sampling_refuses_a_length_that_cannot_advance() raises:
    # v(u) = b u + c u^2 has v(0.3) = v(0.6) = 5e18. The second step adds
    # 0.3 m, which is less than half a unit in the last place of 5e18.
    var c = -5e18 / 0.18
    var b = -0.9 * c
    with assert_raises(contains="cannot advance its length"):
        _ = with_poly3_si(_line(1e300), 0.0, b, c, 0.0)


def test_param_poly3_sample_budget_refuses() raises:
    var u = CubicPolynomial.from_coefficients(0.0, 1.0, 0.0, 0.0, 0.0)
    var v = CubicPolynomial.from_coefficients(0.0, 0.0, 0.0, 0.0, 0.0)
    # Two intervals per meter are past the Int range.
    with assert_raises(contains="exceeds its sample budget"):
        _ = param_poly3_from_coefficients(
            Length(0.0),
            Length(0.0),
            Length(0.0),
            Angle(0.0),
            Length(Float32(5e18)),
            u,
            v,
            ARC_LENGTH,
        )
    # One meter needs the minimum of five intervals, more than three.
    with assert_raises(contains="exceeds its sample budget"):
        _ = param_poly3_from_coefficients(
            Length(0.0),
            Length(0.0),
            Length(0.0),
            Angle(0.0),
            Length(1.0),
            u,
            v,
            ARC_LENGTH,
            max_samples=3,
        )


def test_record_check_refuses_a_flat_arc() raises:
    var record = _line(1.0)
    record.kind = ARC
    record.curvature_start = 0.0
    record.curvature_end = 0.0
    with assert_raises(contains="nonzero curvature"):
        _ = record.pos_at_meters(0.5)


def test_record_check_refuses_bad_sample_tables() raises:
    var short = _poly3()
    short.samples.clear()
    with assert_raises(contains="at least two samples"):
        _ = short.pos_at_meters(0.5)
    var repeated = _poly3()
    repeated.samples[1].s = repeated.samples[0].s
    with assert_raises(contains="strictly increase"):
        _ = repeated.pos_at_meters(0.5)
    var late = _poly3()
    late.samples[0].s = 0.5 * late.samples[1].s
    with assert_raises(contains="begin at zero length"):
        _ = late.pos_at_meters(0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
