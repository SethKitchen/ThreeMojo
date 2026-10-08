# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Source-only helpers for immutable SPIRAL domain-proof controls.

These fixtures reconstruct road 5's stored reference and lane expressions.
They do not load or rebuild the town index, change a test gate, or replace the
canonical scalar evaluator. Exact-polynomial oracles live in a separate suite.
"""

from extensions.carla.curve_bounds import _lane_jet_capture
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.lane_refinement import _checked_center
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
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _SpiralRootCapture,
    _try_pack_spiral_proof,
)
from std.memory import bitcast
from std.testing import assert_equal, assert_true


def _f64(word: UInt64) -> Float64:
    return bitcast[DType.float64](word)


def _bits(one: Float64, two: Float64) raises:
    assert_equal(bitcast[DType.uint64](one), bitcast[DType.uint64](two))


def _interval_bits(one: _Interval, two: _Interval) raises:
    _bits(one.low, two.low)
    _bits(one.high, two.high)


def _jet_bits(one: _Jet, two: _Jet) raises:
    _interval_bits(one.value, two.value)
    _interval_bits(one.first, two.first)
    _interval_bits(one.second, two.second)
    _bits(one.error, two.error)


def _point_bits(
    one: Tuple[_Jet, _Jet, _Jet], two: Tuple[_Jet, _Jet, _Jet]
) raises:
    _jet_bits(one[0], two[0])
    _jet_bits(one[1], two[1])
    _jet_bits(one[2], two[2])


def _encloses(bound: _Interval, low: UInt64, high: UInt64) raises:
    assert_true(bound.is_finite())
    assert_true(bound.contains(_f64(low)))
    assert_true(bound.contains(_f64(high)))


def _geometry() raises -> RoadGeometry:
    var geometry = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_end = 0.05
    return geometry^


def _road(var geometry: RoadGeometry, record_s: Float64 = 0.0) raises -> Road:
    geometry.s = record_s
    var road = Road(
        RoadId(5),
        "SPIRAL proof control",
        record_s + geometry.length,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(3.5))
    )
    road.info.geometries.append(RoadInfoGeometry(record_s, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(1.0, 0.02, 0.0, 0.0, 0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.5))
    )
    return road^


def _capture(
    road: Road, low: Float64, high: Float64, lane: Int = 0
) raises -> _SpiralRootCapture:
    var captured = _SpiralRootCapture()
    _ = _lane_jet_capture(road, 0, lane, low, high, captured)
    return captured


def _proof(
    road: Road,
    low: Float64,
    high: Float64,
    segment_index: Int = 0,
    lane: Int = 0,
) raises -> _SpiralDomainProof:
    var captured = _capture(road, low, high, lane)
    var terms = 0
    var units = 0
    var found = _try_pack_spiral_proof(
        road,
        low,
        high,
        segment_index,
        captured,
        0,
        terms,
        units,
    )
    if not found:
        raise Error("Expected complete immutable root proof")
    var branches = 1 if captured.first_count == captured.last_count else 2
    assert_equal(terms, 16 + 128 * branches)
    assert_equal(units, terms)
    return found.value()


def _canonical_contains(
    road: Road,
    lane: Int,
    point: Tuple[_Jet, _Jet, _Jet],
    station: Float64,
) raises:
    # This is the production Float64 scalar lane center, including CARLA's Y
    # reflection. It is not a moment-polynomial or ideal-trig sample.
    var terms = 0
    var scalar = _checked_center(road, 0, lane, station, terms, 2000000)
    assert_true(point[0].rounded_value().contains(scalar[0]))
    assert_true((-point[1].rounded_value()).contains(scalar[1]))
    assert_true(point[2].rounded_value().contains(scalar[2]))
