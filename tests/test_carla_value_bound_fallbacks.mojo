# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Point oracles and conservative failure paths for CARLA value bounds."""

from extensions.carla.curve_interval import _Interval, _Jet, _ValueJet
from extensions.carla.curve_bounds import (
    _sample_jet,
    _square_jet,
    _reference_jet,
    _finite_spiral_ideal_branch,
    _try_lane_envelope_capture,
    _lane_width_box,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_trig import _curve_atan2
from extensions.carla.geometry import LINE, PARAM_POLY3, _Sample
from extensions.carla.lane_value_bounds import (
    _atan_value,
    _atan2_value,
    _sample_value,
    _reference_sampled_value,
    _lane_value_bound,
)
from extensions.carla.junction_bounds import (
    _outward_float,
    _centered_elevation_enclosure,
    _monotone_coordinate_enclosure,
    _reserve_reference_point,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.road_info import (
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoElevation,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
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
from tests._spiral_domain_controls import _geometry, _road, _proof


def test_atan2_value_encloses_scalar_axes_and_quadrants() raises:
    for x in [-4.0, -1.0, 0.0, 1.0, 4.0]:
        for y in [-4.0, -1.0, 0.0, 1.0, 4.0]:
            var result = _atan2_value(
                _ValueJet.constant(y), _ValueJet.constant(x)
            )
            assert_true(result.rounded_value().contains(_curve_atan2(y, x)))
    var unknown = _ValueJet.variable(
        -inf[DType.float64](), inf[DType.float64]()
    )
    var x_unknown = _atan2_value(_ValueJet.constant(1.0), unknown)
    var y_unknown = _atan2_value(unknown, _ValueJet.constant(1.0))
    assert_true(x_unknown.rounded_value().contains(-3.0))
    assert_true(x_unknown.rounded_value().contains(3.0))
    assert_true(y_unknown.rounded_value().contains(-3.0))
    assert_true(y_unknown.rounded_value().contains(3.0))
    var angle = _atan_value(unknown).rounded_value()
    assert_true(angle.contains(-1.5))
    assert_true(angle.contains(1.5))
    var cut = _atan2_value(
        _ValueJet.variable(-0.5, 0.5), _ValueJet.variable(-4.0, -2.0)
    ).rounded_value()
    assert_true(cut.contains(-3.0))
    assert_true(cut.contains(3.0))
    var signed_zero = _ValueJet.variable(-0.0, 0.0)
    var signed_cut = _atan2_value(
        signed_zero, _ValueJet.constant(-1.0)
    ).rounded_value()
    assert_true(signed_cut.contains(-3.0))
    assert_true(signed_cut.contains(3.0))


def test_sample_heading_uses_both_stored_horizontal_tangents() raises:
    for kind in range(4):
        var geometry = _geometry()
        geometry.kind = PARAM_POLY3
        var tangent = -1.0 if kind == 0 else 0.0
        var second_vertical = 1.0 if kind == 2 else 0.0
        var first_vertical = -0.0 if kind == 3 else 0.0
        geometry.samples.append(_Sample(0.0, 0.0, 0.0, tangent, first_vertical))
        geometry.samples.append(
            _Sample(1.0, 0.0, 1.0, tangent, second_vertical)
        )
        var full = _sample_jet(
            geometry, _Jet.variable(0.5, 0.5), 0, Vector3(0, 0, 0)
        )
        var value = _sample_value(
            geometry, _ValueJet.variable(0.5, 0.5), 0, Vector3(0, 0, 0)
        )
        var expected = _curve_atan2(
            0.5 * first_vertical + 0.5 * second_vertical, tangent
        )
        assert_true(full[2].rounded_value().contains(expected))
        assert_true(value[2].rounded_value().contains(expected))


def test_sampled_missing_and_wide_records_return_unknown() raises:
    var geometry = _geometry()
    geometry.kind = LINE
    var unsupported = _reference_sampled_value(
        geometry, _ValueJet.variable(0.25, 0.5), Vector3(0, 0, 0)
    )
    assert_false(unsupported[0].rounded_value().is_finite())
    geometry.kind = PARAM_POLY3
    var empty = _reference_sampled_value(
        geometry, _ValueJet.variable(0.25, 0.5), Vector3(0, 0, 0)
    )
    assert_false(empty[0].rounded_value().is_finite())
    for i in range(4):
        geometry.samples.append(_Sample(Float64(i), 0.0, Float64(i), 1.0, 0.0))
    var wide = _reference_sampled_value(
        geometry, _ValueJet.variable(0.25, 2.75), Vector3(0, 0, 0)
    )
    assert_false(wide[0].rounded_value().is_finite())
    geometry.kind = LINE
    var line = _reference_jet(
        geometry, _Jet.variable(0.25, 0.5), Vector3(0, 0, 0)
    )
    assert_true(line[0].rounded_value().contains(0.25))
    assert_true(line[0].rounded_value().contains(0.5))
    var squared = _square_jet(_Jet.variable(-2.0, 3.0))
    assert_true(squared.value.contains(0.0))
    assert_true(squared.value.contains(9.0))
    assert_true(squared.value.low >= 0.0)


def test_ideal_branch_rejects_each_nonfinite_field() raises:
    for kind in range(4):
        var value = _Jet.constant(1.0)
        if kind == 1:
            value.value = _Interval.whole()
        elif kind == 2:
            value.first = _Interval.whole()
        elif kind == 3:
            value.second = _Interval.whole()
        assert_equal(
            _finite_spiral_ideal_branch(
                (value, _Jet.constant(0.0), _Jet.constant(0.0))
            ),
            kind == 0,
        )


def test_optional_lane_helpers_reject_structure_without_term_debit() raises:
    for kind in range(8):
        var road = _road(_geometry())
        var low = 2.125
        var high = 2.25
        if kind == 0:
            road.info.geometries.clear()
        elif kind == 1:
            road.info.geometries.append(RoadInfoGeometry(2.2, _geometry()))
        elif kind == 2:
            road.info.geometries[0].geometry.kind = LINE
        elif kind == 3:
            road.info.geometries[0].geometry.heading = 0.1
        elif kind == 4:
            road.info.geometries[0].geometry.curvature_start = 0.1
        elif kind == 5:
            road.info.geometries[0].geometry.curvature_end = 1e100
        elif kind == 6:
            road.info.geometries[0].geometry.length = 100.0
            low = 70.0
            high = 70.25
        else:
            low = 1.0
            high = 5.0
        var nodes = 0
        var terms = 0
        assert_false(
            Bool(
                _try_grouped_lane_jet(
                    road, 0, 0, low, high, nodes, terms, 100, 10000
                )
            )
        )
        assert_equal(nodes, 1)
        assert_equal(terms, 0)
        var captured = _SpiralRootCapture()
        assert_false(
            Bool(
                _try_lane_envelope_capture(
                    road, 0, 0, low, high, captured, terms, 10000
                )
            )
        )
        assert_equal(terms, 0)


def test_lane_record_errors_and_crossed_profiles_are_unknown() raises:
    for kind in range(4):
        var geometry = _geometry()
        geometry.kind = LINE
        var road = _road(geometry^)
        if kind == 0:
            road.info.geometries.clear()
        elif kind == 1:
            road.info.lane_offsets.clear()
        elif kind == 2:
            road.sections[0].lanes[0].info.widths.clear()
        else:
            road.info.lane_offsets.append(
                RoadInfoLaneOffset(2.2, CubicPolynomial.constant(0.0))
            )
        if kind < 3:
            with assert_raises():
                _ = _lane_value_bound(road, 0, 0, 2.125, 2.25)
        else:
            var point = _lane_value_bound(road, 0, 0, 2.125, 2.25)
            assert_false(point[0].rounded_value().is_finite())
    var road = _road(_geometry())
    road.sections[0].lanes[0].info.widths.clear()
    with assert_raises(contains="width record"):
        _ = _lane_width_box(road, 0, 0, 2.125, 2.25)
    road.info.geometries.clear()
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="quadrature work"):
        _reserve_reference_point(road, 2.125, work)


def test_outward_float_encloses_subnormals_and_refuses_overflow() raises:
    var smallest = Float64(bitcast[DType.float32](UInt32(1)))
    assert_equal(
        bitcast[DType.uint32](_outward_float(-smallest * 0.25, True)),
        UInt32(0x80000001),
    )
    assert_equal(
        bitcast[DType.uint32](_outward_float(smallest * 0.25, False)), UInt32(1)
    )
    for lower in [False, True]:
        with assert_raises(contains="public storage"):
            _ = _outward_float(inf[DType.float64](), lower)
    var maximum = Float64(bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    with assert_raises(contains="public storage"):
        _ = _outward_float(maximum * (1.0 + 1e-9), False)


def test_centered_and_monotone_enclosures_keep_original_on_failure() raises:
    var original = _Interval(-10.0, 10.0)
    for kind in range(5):
        var road = _road(_geometry())
        var error = 0.0
        if kind == 0:
            error = inf[DType.float64]()
        elif kind == 1:
            error = -1.0
        elif kind == 2:
            road.info.elevations.clear()
        elif kind == 3:
            road.info.elevations.append(
                RoadInfoElevation(2.2, CubicPolynomial.constant(0.0))
            )
        else:
            road.info.elevations[0].polynomial = CubicPolynomial.constant(100.0)
        var work = _MapBuildWork(MapBuildBudget())
        var result = _centered_elevation_enclosure(
            road, 2.125, 2.25, original, error, work
        )
        assert_equal(result.low, original.low)
        assert_equal(result.high, original.high)
        assert_equal(work.steps, 1)
        assert_equal(work.terms, 128)
    var value = _Jet.variable(0.0, 1.0)
    var disjoint = _monotone_coordinate_enclosure(
        value, _Interval.point(100.0), _Interval.point(101.0), original
    )
    assert_equal(disjoint.low, original.low)
    assert_equal(disjoint.high, original.high)


def test_proof_expansion_rejects_nonfinite_station_and_missing_geometry() raises:
    var road = _road(_geometry())
    var proof = _proof(road, 2.125, 2.25)
    var location = Vector3(0, 0, 0)
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                road, 0, 0, nan, location, 1.0, 2.125, 2.25, proof
            )
        )
    )
    road.info.geometries.clear()
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                road, 0, 0, 2.2, location, 1.0, 2.125, 2.25, proof
            )
        )
    )
    var geometry = _geometry()
    geometry.kind = LINE
    road = _road(geometry^)
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                road, 0, 0, 2.2, location, 1.0, 2.125, 2.25, proof
            )
        )
    )


def test_reversed_query_is_refused_after_its_attempt_debit() raises:
    var road = _road(_geometry())
    var captured = _SpiralRootCapture()
    var terms = 0
    assert_false(
        Bool(
            _try_lane_envelope_capture(
                road, 0, 0, 3.0, 2.0, captured, terms, 10000
            )
        )
    )
    assert_equal(terms, 2048)
    assert_equal(captured.record_at, -1)
    var nodes = 0
    terms = 0
    assert_false(
        Bool(
            _try_grouped_lane_jet(
                road, 0, 0, 3.0, 2.0, nodes, terms, 100, 10000
            )
        )
    )
    assert_equal(nodes, 1)
    assert_equal(terms, 24)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
