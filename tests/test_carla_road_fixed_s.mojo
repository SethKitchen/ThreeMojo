# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent fixed-s OpenDRIVE controls for issue #604."""

from extensions.carla.curve_distance import _wide_distance
from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LANE_SIDEWALK,
    LANE_TRAM,
    LaneId,
    LaneType,
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
    assert_raises,
    assert_true,
)


def _lane(mut road: Road, section: Int, id: Int, width: Float64) raises:
    var lane = road.sections[section].add_lane(LaneId(id))
    road.sections[section].lanes[lane].type = LANE_DRIVING
    road.sections[section].lanes[lane].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(width))
    )


def _road(
    x: Float64 = 0,
    y: Float64 = 0,
    z: Float64 = 0,
    width: Float64 = 2,
) raises -> Road:
    var road = Road(
        RoadId(1), "fixed-s", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    # Insert left first to check that storage order remains lane-id order.
    _lane(road, 0, 1, width)
    _lane(road, 0, -1, width)
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, x, y, 0.0, 10.0))
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(z))
    )
    return road^


def _winner(road: Road, s: Float64, query: Vector3, id: Int) raises -> Float64:
    var result = road.nearest_lane(s, query)
    assert_true(Bool(result[0]))
    assert_equal(result[0].value().lane_id.value, id)
    return result[1]


def test_translated_origin_keeps_the_unique_lane() raises:
    var road = _road(y=1000000001.0)
    assert_equal(_winner(road, 5, Vector3(5, 1000000000, 0), -1), 0.0)
    road = _road(y=-1000000001.0)
    assert_equal(_winner(road, 5, Vector3(5, -1000000000, 0), 1), 0.0)
    road = _road(x=1000000001.0, y=1000000001.0)
    assert_equal(_winner(road, 0, Vector3(1000000000, 1000000000, 0), -1), 1.0)


def test_tiny_width_centers_and_positive_distance_survive() raises:
    var tiny = Float64(1e-200)
    var road = _road(y=tiny, width=2.0 * tiny)
    # Exact stored centers are zero and 2*tiny; a zero square is no tie.
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), -1), 0.0)
    road = _road(width=2.0 * tiny)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), 1), tiny)
    var eta = bitcast[DType.float64](UInt64(1))
    road = _road(y=eta, width=2.0 * eta)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), -1), 0.0)
    road = _road(width=2.0 * eta)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), 1), eta)


def test_wide_widths_offsets_and_elevation_do_not_narrow() raises:
    var road = _road(y=5e99, width=1e100)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), -1), 0.0)
    road = _road(width=2e-200)
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1e-200))
    )
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), -1), 0.0)
    road = _road(z=1e-200, width=0)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), 1), 1e-200)


def test_wide_record_values_keep_a_real_unit_gap() raises:
    var road = _road(width=33554434.0)
    assert_equal(_winner(road, 0, Vector3(0, -16777216, 0), -1), 1.0)
    road = _road(width=0)
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(16777217.0))
    )
    assert_equal(_winner(road, 0, Vector3(0, 16777216, 0), 1), 1.0)
    road = _road(z=16777217.0, width=0)
    assert_equal(_winner(road, 0, Vector3(0, 0, 16777216), 1), 1.0)


def test_true_ties_and_same_side_ties_keep_the_later_lane() raises:
    var road = _road()
    assert_equal(_winner(road, 5, Vector3(5, 0, 0), 1), 1.0)
    _lane(road, 0, -2, 2)
    assert_equal(_winner(road, 5, Vector3(5, -2, 0), -2), 1.0)
    road = _road(width=0)
    _lane(road, 0, 2, 0)
    assert_equal(_winner(road, 5, Vector3(5, 0, 0), 2), 0.0)
    road.sections[0].lanes[2].type = LANE_SIDEWALK
    var result = road.nearest_lane(5, Vector3(5, 0, 0), LANE_DRIVING)
    assert_equal(result[0].value().lane_id.value, 1)


def test_filters_no_match_and_center_lane_exclusion() raises:
    var road = _road()
    road.sections[0].lanes[1].type = LANE_SIDEWALK
    var result = road.nearest_lane(5, Vector3(5, 1, 0), LANE_DRIVING)
    assert_equal(result[0].value().lane_id.value, -1)
    assert_equal(result[1], 2.0)
    result = road.nearest_lane(5, Vector3(5, 1, 0), LANE_TRAM)
    assert_false(Bool(result[0]))
    assert_equal(result[1], 1.7976931348623157e308)
    _ = road.sections[0].add_lane(LaneId(0))
    assert_equal(_winner(road, 5, Vector3(5, 0, 0), 1), 1.0)
    road.sections[0].lanes.clear()
    result = road.nearest_lane(5, Vector3(5, 0, 0))
    assert_false(Bool(result[0]))
    assert_equal(result[1], 1.7976931348623157e308)


def test_section_merge_and_boundary_keep_existing_rules() raises:
    var road = _road()
    _ = road.add_section(SectionId(7), 0)
    _lane(road, 1, -1, 4)
    # Duplicate -1 comes from the later section; +1 remains in section 0.
    var result = road.nearest_lane(5, Vector3(5, -2, 0))
    assert_equal(result[0].value().section_id.value, 7)
    assert_equal(result[0].value().lane_id.value, -1)
    assert_equal(result[1], 0.0)
    assert_equal(_winner(road, 5, Vector3(5, 1, 0), 1), 0.0)
    _ = road.add_section(SectionId(8), 5)
    _lane(road, 2, -2, 6)
    result = road.nearest_lane(5, Vector3(5, -3, 0))
    assert_equal(result[0].value().section_id.value, 8)
    assert_equal(result[0].value().lane_id.value, -2)
    assert_equal(result[1], 0.0)


def test_plan_and_offset_clamp_but_width_and_elevation_use_given_s() raises:
    var road = _road(width=0)
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial(0, 1, 0, 0, 0))
    )
    road.info.elevations[0] = RoadInfoElevation(
        0.0, CubicPolynomial(0, 1, 0, 0, 0)
    )
    road.sections[0].lanes[0].info.widths[0] = RoadInfoLaneWidth(
        0.0, CubicPolynomial(0, 2, 0, 0, 0)
    )
    # s=12: plan x=10, offset y=10, right half-width=12, elevation z=12.
    assert_equal(_winner(road, 12, Vector3(10, -2, 12), -1), 0.0)
    road.sections[0].s = -2
    road.info.elevations[0].s = -2
    road.sections[0].lanes[0].info.widths[0].s = -2
    road.sections[0].lanes[1].info.widths[0].s = -2
    # s=-1: plan and lane offset clamp to zero; width/elevation remain -1.
    assert_equal(_winner(road, -1, Vector3(0, 1, -1), -1), 0.0)


def test_outer_centers_are_checked_and_signed_widths_can_reverse() raises:
    var road = _road()
    _lane(road, 0, -2, 2)
    _ = road.sections[0].add_lane(LaneId(-3))
    # The old early stop hid this missing outer width record.
    with assert_raises(contains="no width record"):
        _ = road.nearest_lane(5, Vector3(5, -1, 0))
    road = _road()
    _lane(road, 0, -2, 2)
    _lane(road, 0, -3, -14)
    _ = road.sections[0].lanes.pop()
    # Finite signed widths remain admitted; every computed center is tested.
    assert_equal(_winner(road, 0, Vector3(0, 5, 0), -3), 2.0)


def test_nonnegative_rounded_centers_do_not_justify_an_early_stop() raises:
    var query_x = Float32(1e16)
    var road = _road(width=1)
    _ = road.sections[0].lanes.pop()
    _lane(road, 0, -2, 1)
    _lane(road, 0, -3, 10)
    road.info.geometries[0] = RoadInfoGeometry(
        0.0,
        RoadGeometry(
            LINE, 0.0, Float64(query_x) - 100.0, 0.0, 0.7853981633974483, 10.0
        ),
    )
    # At this x, an individual 0.5*sin(heading) step rounds away. The
    # second center is farther than the first, but the third is closer.
    # Stored-point Fraction controls independently establish this order.
    var distance = _winner(road, 0, Vector3(query_x, 0, 0), -3)
    assert_true(distance > 96.0)
    assert_true(distance < 97.0)


def test_finite_extremes_do_not_use_rounded_output_for_selection() raises:
    var road = _road(y=1e300, width=1e285)
    # The right center is strictly closer even though Float32 would overflow.
    var distance = _winner(road, 0, Vector3(0, 0, 0), -1)
    assert_true(distance > 0)
    assert_true(distance < 1e300)
    road = _road(y=1e100, z=1e200, width=2e100)
    # Squared Float64 norms both overflow; actual stored-point order is unique.
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), -1), 1e200)


def test_only_the_final_winner_needs_a_representable_norm() raises:
    var road = _road(x=1.3e308, y=-1.3e308, width=0)
    road.sections[0].lanes[1].info.widths[0] = RoadInfoLaneWidth(
        0.0, CubicPolynomial.constant(1.7976931348623157e308)
    )
    # The first right center's norm exceeds Float64; the later left winner
    # has a finite norm. Selection must finish before evaluating the output.
    var distance = _winner(road, 0, Vector3(0, 0, 0), 1)
    assert_true(distance > 1.3e308)
    assert_true(distance < 1.7976931348623157e308)


def test_nonfinite_queries_and_s_raise_before_an_empty_result() raises:
    var road = _road()
    road.sections[0].lanes.clear()
    var bad = inf[DType.float32]()
    var nan = bitcast[DType.float32](UInt32(0x7FC00000))
    for query in [Vector3(bad, 0, 0), Vector3(0, nan, 0), Vector3(0, 0, -bad)]:
        with assert_raises(contains="finite coordinates"):
            _ = road.nearest_lane(0, query)
    for s in [
        inf[DType.float64](),
        -inf[DType.float64](),
        bitcast[DType.float64](UInt64(0x7FF8000000000000)),
    ]:
        with assert_raises(contains="finite s"):
            _ = road.nearest_lane(s, Vector3(0, 0, 0))
    with assert_raises(contains="Lane type is not valid"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0), LaneType(0))


def test_nonfinite_visited_widths_and_centers_raise() raises:
    var road = _road(width=inf[DType.float64]())
    with assert_raises(contains="finite width"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road(width=bitcast[DType.float64](UInt64(0x7FF8000000000000)))
    with assert_raises(contains="finite width"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road()
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(inf[DType.float64]()))
    )
    with assert_raises(contains="finite coordinates"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road(z=inf[DType.float64]())
    with assert_raises(contains="finite coordinates"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road(y=inf[DType.float64]())
    with assert_raises(contains="finite coordinates"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road(y=1.7e308, width=1.7e308)
    with assert_raises(contains="finite coordinates"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))
    road = _road()
    road.sections[0].lanes[0].info.widths.clear()
    with assert_raises(contains="no width record"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))


def test_scale_safe_distance_and_exact_overflow_edge() raises:
    var zero = Array[Float64, 3](fill=0.0)
    assert_equal(_wide_distance(zero, zero), 0.0)
    assert_equal(_wide_distance([3.0, 4.0, 0.0], zero), 5.0)
    var eta = bitcast[DType.float64](UInt64(1))
    assert_equal(_wide_distance([eta, 0.0, 0.0], zero), eta)
    assert_almost_equal(
        _wide_distance([1.0, 1.0, 1.0], zero), 1.7320508075688772, atol=1e-15
    )
    var limit = Float64(1.7976931348623157e308)
    assert_equal(_wide_distance([limit, 0.0, 0.0], zero), limit)
    # Fraction certifies this stored-bit norm is below DOUBLE_MAX. The naive
    # normalized reconstruction overflows because of its final rounding.
    var a = bitcast[DType.float64](UInt64(0x7F554C985F06F693))
    var b = bitcast[DType.float64](UInt64(0x7FEFFFFE3A580905))
    assert_equal(_wide_distance([a, b, 0.0], zero), limit)
    var road = _road(x=a, y=b, width=0)
    assert_equal(_winner(road, 0, Vector3(0, 0, 0), 1), limit)
    with assert_raises(contains="Float64 range"):
        _ = _wide_distance([limit, limit, 0.0], zero)
    with assert_raises(contains="Float64 range"):
        _ = _wide_distance([limit, 0.0, 0.0], [-limit, 0.0, 0.0])
    with assert_raises(contains="finite coordinates"):
        _ = _wide_distance([inf[DType.float64](), 0.0, 0.0], zero)
    road = _road(x=limit, y=limit, width=0)
    with assert_raises(contains="Float64 range"):
        _ = road.nearest_lane(0, Vector3(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
