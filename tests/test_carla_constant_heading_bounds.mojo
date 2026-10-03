# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Fixed-heading provenance and the unchanged diagonal LINE failure."""

from extensions.carla.curve_bounds import _lane_jet, _scaled_point_distance_jet
from extensions.carla.curve_interval import _Jet
from extensions.carla.curve_trig import (
    _constant_sincos_jet,
    _curve_sincos,
    _sincos_jet,
    _PHASE_LIMIT,
)
from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.lane_refinement import (
    _refine_lane_certificate,
    _scaled_accuracy,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _assert_fixed_coefficient(bounded: _Jet, actual: Float64) raises:
    assert_true(bounded.rounded_value().contains(actual))
    assert_equal(bounded.first.low, 0.0)
    assert_equal(bounded.first.high, 0.0)
    assert_equal(bounded.second.low, 0.0)
    assert_equal(bounded.second.high, 0.0)
    assert_equal(bounded.error, 0.0)


def test_fixed_headings_keep_zero_derivatives_and_scalar_output_ranges() raises:
    var quarter = Float64(0.7853981633974483)
    var before = bitcast[DType.float64](
        bitcast[DType.uint64](quarter) - UInt64(1)
    )
    var after = bitcast[DType.float64](
        bitcast[DType.uint64](quarter) + UInt64(1)
    )
    for heading in [
        0.0,
        0.1,
        quarter,
        before,
        after,
        -quarter,
        1.5707963267948966,
        2.356194490192345,
        -2.356194490192345,
        _PHASE_LIMIT,
        -_PHASE_LIMIT,
    ]:
        var bounded = _constant_sincos_jet(heading)
        var actual = _curve_sincos(heading)
        _assert_fixed_coefficient(bounded[0], actual[0])
        _assert_fixed_coefficient(bounded[1], actual[1])
    var tenth = _constant_sincos_jet(0.1)
    # Independent exact-rational all-fused/all-unfused Horner witnesses.
    assert_true(
        tenth[1].value.contains(
            bitcast[DType.float64](UInt64(0x3FEFD712F9A817C0))
        )
    )
    assert_true(
        tenth[1].value.contains(
            bitcast[DType.float64](UInt64(0x3FEFD712F9A817C1))
        )
    )


def test_generic_varying_and_singleton_headings_keep_their_uncertainty() raises:
    var quarter = Float64(0.7853981633974483)
    var near_constant = _Jet.constant(quarter) + _Jet.variable(
        -1.0, 1.0
    ) * _Jet.constant(1e-12)
    assert_true(near_constant.first.low > 0.0)
    assert_false(_sincos_jet(near_constant)[0].first.is_finite())
    # An expansion point is not constant-in-s provenance.
    var singleton = _Jet.variable(quarter, quarter)
    assert_false(_sincos_jet(singleton)[0].first.is_finite())
    # Even zero first/second derivatives at a point do not justify replacing
    # a varying expression at a selector discontinuity with a constant leaf.
    var t = _Jet.variable(0.0, 0.0)
    var cubic = _Jet.constant(quarter) + t * t * t
    assert_true(cubic.first.contains(0.0))
    assert_true(cubic.second.contains(0.0))
    assert_false(_sincos_jet(cubic)[0].first.is_finite())


def test_unsupported_fixed_phases_retain_generic_unknown_derivatives() raises:
    var beyond = bitcast[DType.float64](
        bitcast[DType.uint64](Float64(_PHASE_LIMIT)) + UInt64(1)
    )
    for heading in [
        beyond,
        -beyond,
        inf[DType.float64](),
        -inf[DType.float64](),
        bitcast[DType.float64](UInt64(0x7FF8000000000001)),
    ]:
        var result = _constant_sincos_jet(heading)
        assert_false(result[0].first.is_finite())
        assert_false(result[1].second.is_finite())


def test_diagonal_line_has_curvature_and_completes_with_original_limits() raises:
    var length = bitcast[DType.float64](UInt64(0x402C48C6001F0AC0))
    var heading = bitcast[DType.float64](UInt64(0x3FE921FB54442D18))
    var low = bitcast[DType.float64](UInt64(0x3D19000000000000))
    var high = bitcast[DType.float64](UInt64(0x402C48C5DE911B7E))
    var road = Road(
        RoadId(14), "diagonal", length, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(3.5))
    )
    road.info.geometries.append(
        RoadInfoGeometry(
            0.0, RoadGeometry(LINE, 0.0, 55.0, -10.0, heading, length)
        )
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0))
    )
    var query = Vector3(55.25, 5.0, 3.0)
    var domain = _lane_jet(road, 0, 0, low, high)
    var metric = _scaled_point_distance_jet(domain, query, 4.0)
    assert_true(metric.second.is_finite())
    assert_true(metric.second.low > 0.0)
    assert_true(metric.second.contains(0.125))
    for s in [low, 1.0, 3.7123106012293743, 10.0, high]:
        var point = road._lane_center(0, 0, s)
        assert_true(domain[0].rounded_value().contains(point[0]))
        assert_true((-domain[1].rounded_value()).contains(point[1]))
        assert_true(domain[2].rounded_value().contains(point[2]))
    var certificate = _refine_lane_certificate(
        road, 0, 0, low, high, query, low + (high - low) * 0.5, 0.0
    )
    assert_almost_equal(certificate.s, 3.7123106012293743, atol=1e-4)
    var allowance = _scaled_accuracy(
        road,
        0,
        0,
        low,
        high,
        certificate.s,
        certificate.lower,
        certificate.scale,
    )
    assert_true(certificate.upper - certificate.lower <= allowance)
    assert_true(certificate.nodes <= 16384)
    assert_true(certificate.terms <= 2000000)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
