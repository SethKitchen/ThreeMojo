# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Full-domain containment, optional work, and sparse cover controls."""

from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_interval import _Interval, _next_up
from extensions.carla.geometry import (
    ARC,
    LINE,
    PARAM_POLY3,
    POLY3,
    SPIRAL,
    RoadGeometry,
    _Sample,
)
from extensions.carla.lane_box_cover import (
    _LaneBoxCover,
    _lane_cover_can_improve,
    _sampled_lane_box_cover,
)
from extensions.carla.lane_refinement import (
    _checked_center,
    _chord_certificate,
    _finite_lane_box,
    _midpoint,
    _whole_lane_box,
)
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    info_index,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.test_carla_cross_candidate_certificates import _road, _sampled_road
from tests.test_carla_scaled_lane_refinement import _scaled_road


def _boxes(
    cover: _LaneBoxCover,
) -> Array[Tuple[_Interval, _Interval, _Interval], 4]:
    return [cover.first, cover.second, cover.third, cover.fourth]


def _assert_contains(
    box: Tuple[_Interval, _Interval, _Interval], point: Array[Float64, 3]
) raises:
    assert_true(box[0].contains(point[0]))
    assert_true(box[1].contains(point[1]))
    assert_true(box[2].contains(point[2]))


def _assert_full_cells(road: Road, low: Float64, high: Float64) raises:
    var terms = 0
    var result = _sampled_lane_box_cover(road, 0, 0, low, high, terms, 4)
    assert_true(Bool(result))
    assert_equal(terms, 4)
    var boxes = _boxes(result.value())
    var middle = _midpoint(low, high)
    var edges: Array[Float64, 5] = [
        low,
        _midpoint(low, middle),
        middle,
        _midpoint(middle, high),
        high,
    ]
    var scalar_terms = 0
    for cell in range(4):
        assert_true(_finite_lane_box(boxes[cell]))
        for i in range(33):
            var s = (
                edges[cell]
                + (edges[cell + 1] - edges[cell]) * Float64(i) / 32.0
            )
            var point = _checked_center(road, 0, 0, s, scalar_terms, 135)
            _assert_contains(boxes[cell], point)
        # Both boxes must contain their common boundary, with no gap.
        if cell < 3:
            var point = _checked_center(
                road, 0, 0, edges[cell + 1], scalar_terms, 135
            )
            _assert_contains(boxes[cell], point)
            _assert_contains(boxes[cell + 1], point)


def test_complete_cover_contains_canonical_centers_and_independent_fixtures() raises:
    # Existing independent fixtures have u=(2s-1)*scale, v=2*scale,
    # and a known minimum at s=1/2. Exercise both sampled geometry kinds.
    for scale in [Float64(1e-200), Float64(1.0), Float64(1e200)]:
        var road = _scaled_road(scale)
        for kind in [PARAM_POLY3, POLY3]:
            road.info.geometries[0].geometry.kind = kind
            _assert_full_cells(road, 0.0, 1.0)
            var terms = 0
            var result = _sampled_lane_box_cover(road, 0, 0, 0, 1, terms)
            var cover = result.value()
            # These exact fixture values are independent of the bounds.
            _assert_contains(cover.first, [-scale, -2.0 * scale, 0.0])
            _assert_contains(cover.second, [0.0, -2.0 * scale, 0.0])
            _assert_contains(cover.third, [0.0, -2.0 * scale, 0.0])
            _assert_contains(cover.fourth, [scale, -2.0 * scale, 0.0])
            assert_true(
                _lane_cover_can_improve(
                    cover, Vector3(0, 0, 0), [0.0, -2.0 * scale, 0.0]
                )
            )


def test_between_quarter_peak_is_enclosed_as_a_complete_interval() raises:
    var road = _sampled_road(1.0)
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    geometry.samples.append(_Sample(0.0, 0.0, 0.0, 1.0, 0.0))
    geometry.samples.append(_Sample(0.125, 0.005, 0.125, 1.0, 0.0))
    geometry.samples.append(_Sample(1.0, 0.0, 1.0, 1.0, 0.0))
    road.info.geometries[0] = RoadInfoGeometry(0.0, geometry^)
    _assert_full_cells(road, 0.0, 1.0)
    var terms = 0
    var cover = _sampled_lane_box_cover(road, 0, 0, 0, 1, terms).value()
    _assert_contains(cover.first, [0.125, -0.005, 0.0])
    assert_true(
        _lane_cover_can_improve(
            cover, Vector3(0.125, -0.005, 0), [0.125, -0.005, 0.0]
        )
    )


def test_optional_cover_charges_before_each_evaluation_and_never_extends_cap() raises:
    var road = _sampled_road(1.0)
    for budget in range(5):
        var terms = 0
        var result = _sampled_lane_box_cover(road, 0, 0, 0, 1, terms, budget)
        assert_equal(Bool(result), budget == 4)
        assert_equal(terms, budget)
        # Every allowance from 0 through 4 must fall back if prior work
        # leaves fewer than four terms. Preserve the original spent count.
        terms = 1
        result = _sampled_lane_box_cover(road, 0, 0, 0, 1, terms, budget)
        assert_false(Bool(result))
        assert_equal(terms, max(1, budget))
    var chord = _chord_certificate(
        road, 0, 0, 0, 1, Vector3(-1, -2, 0), Vector3(1, -2, 0)
    )
    var original = chord[2]
    var terms = original
    assert_false(
        Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, original + 3))
    )
    assert_equal(terms, original + 3)
    terms = original
    assert_true(
        Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, original + 4))
    )
    assert_equal(terms, original + 4)
    assert_equal(chord[2], original)
    terms = 1999997
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 2000000)
    terms = -1
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, -1)


def test_reversed_degenerate_and_adjacent_station_domains() raises:
    var road = _sampled_road(1.0)
    var terms = 0
    var forward = _sampled_lane_box_cover(road, 0, 0, 0, 1, terms).value()
    terms = 0
    var reversed = _sampled_lane_box_cover(road, 0, 0, 1, 0, terms).value()
    var one = _boxes(forward)
    var two = _boxes(reversed)
    for i in range(4):
        assert_equal(one[i][0].low, two[i][0].low)
        assert_equal(one[i][0].high, two[i][0].high)
        assert_equal(one[i][1].low, two[i][1].low)
        assert_equal(one[i][1].high, two[i][1].high)
        assert_equal(one[i][2].low, two[i][2].low)
        assert_equal(one[i][2].high, two[i][2].high)
    for high in [0.5, _next_up(0.5), _next_up(_next_up(0.5))]:
        terms = 0
        assert_false(
            Bool(_sampled_lane_box_cover(road, 0, 0, 0.5, high, terms))
        )
        assert_equal(terms, 0)
    for bad in [inf[DType.float64](), -inf[DType.float64](), -1.0]:
        terms = 0
        assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, bad, 1, terms)))
        assert_equal(terms, 0)


def test_unsupported_missing_and_unknown_enclosures_keep_old_path() raises:
    var road = _sampled_road(1.0)
    for kind in [LINE, ARC, SPIRAL]:
        road.info.geometries[0].geometry.kind = kind
        var terms = 7
        assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
        assert_equal(terms, 7)
    road = _sampled_road(1.0)
    road.info.geometries[0].geometry.samples.clear()
    var terms = 0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 0)
    road = _sampled_road(1.0)
    road.info.geometries[0].geometry.length = 0.0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 0)
    road = _sampled_road(1.0)
    road.info.elevations.clear()
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 1)
    # A cell spanning too many sampled branches is unknown.
    road = _sampled_road(1.0)
    ref samples = road.info.geometries[0].geometry.samples
    samples.clear()
    for i in range(17):
        var s = Float64(i) / 16.0
        samples.append(_Sample(s, 0.0, s, 1.0, 0.0))
    terms = 0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 1)
    # Three finite cells followed by an unknown last cell must also fall
    # back. No finite prefix can be stored as if it covered the whole lane.
    samples.clear()
    for s in [0.0, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0]:
        samples.append(_Sample(s, 0.0, s, 1.0, 0.0))
    terms = 0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, 4)))
    assert_equal(terms, 4)


def test_record_changes_do_not_create_a_partial_cover() raises:
    var road = _sampled_road(1.0)
    var other = _sampled_road(1.0)
    road.info.geometries.append(
        RoadInfoGeometry(0.5, other.info.geometries[0].geometry.copy())
    )
    var terms = 0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
    assert_equal(terms, 0)
    for which in range(3):
        road = _sampled_road(1.0)
        if which == 0:
            road.info.elevations.append(
                RoadInfoElevation(0.5, CubicPolynomial.constant(1.0))
            )
        elif which == 1:
            road.info.lane_offsets.append(
                RoadInfoLaneOffset(0.5, CubicPolynomial.constant(3.0))
            )
        else:
            road.sections[0].lanes[0].info.widths.append(
                RoadInfoLaneWidth(0.5, CubicPolynomial.constant(3.0))
            )
        terms = 0
        assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms)))
        assert_equal(terms, 2)


def _point_box(x: Float64) -> Tuple[_Interval, _Interval, _Interval]:
    return (_Interval.point(x), _Interval.point(0.0), _Interval.point(0.0))


def test_only_four_strict_exclusions_can_reject_a_candidate() raises:
    var far = _point_box(4.0)
    var tie = _point_box(-1.0)
    var winner = _point_box(0.5)
    var best: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var query = Vector3(0, 0, 0)
    assert_false(
        _lane_cover_can_improve(_LaneBoxCover(far, far, far, far), query, best)
    )
    for possible in [tie, winner, _whole_lane_box()]:
        assert_true(
            _lane_cover_can_improve(
                _LaneBoxCover(possible, far, far, far), query, best
            )
        )
        assert_true(
            _lane_cover_can_improve(
                _LaneBoxCover(far, possible, far, far), query, best
            )
        )
        assert_true(
            _lane_cover_can_improve(
                _LaneBoxCover(far, far, possible, far), query, best
            )
        )
        assert_true(
            _lane_cover_can_improve(
                _LaneBoxCover(far, far, far, possible), query, best
            )
        )
    assert_true(
        _lane_cover_can_improve(
            _LaneBoxCover(far, far, far, far),
            query,
            [inf[DType.float64](), 0.0, 0.0],
        )
    )
    var zero = _point_box(0.0)
    assert_true(
        _lane_cover_can_improve(
            _LaneBoxCover(zero, zero, zero, zero), query, [0.0, 0.0, 0.0]
        )
    )


def test_sparse_map_ownership_retains_public_order_ties_and_strict_width() raises:
    var roads = List[Road]()
    var one = _sampled_road(1.0)
    one.id = RoadId(1)
    roads.append(one^)
    var two = _sampled_road(1.0)
    two.id = RoadId(2)
    roads.append(two^)
    roads.append(_road(3, 10.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var allocated = 0
    var absent = 0
    for i in range(map.segment_count()):
        var public = map.segment(i)
        ref segment = map._segments[i]
        assert_equal(public[2].road_id, segment.first.road_id)
        assert_equal(public[3].lane_id, segment.second.lane_id)
        assert_equal(public[2].s, segment.first.s)
        assert_equal(public[3].s, segment.second.s)
        if public[2].road_id == RoadId(3):
            assert_equal(segment.cover_index, -1)
            absent += 1
        else:
            assert_equal(segment.cover_index, allocated)
            allocated += 1
    assert_true(allocated > 0)
    assert_true(absent > 0)
    assert_equal(len(map._sampled_covers), allocated)
    var count = map.segment_count()
    var before = map._sampled_covers[0]
    # Identical sampled lanes must keep the first segment on an exact tie.
    assert_equal(
        map.closest_waypoint_on_road(Vector3(0, -2, 0)).value().road_id,
        RoadId(1),
    )
    assert_true(Bool(map.waypoint(Vector3(0, -2, 0))))
    # The third road is an exact axis LINE with half-width 1. The sampled
    # competitors must not change its established strict boundary result.
    assert_equal(
        map.closest_waypoint_on_road(Vector3(0.5, -10, 0)).value().road_id,
        RoadId(3),
    )
    assert_false(Bool(map.waypoint(Vector3(0.5, -9, 0))))
    assert_equal(map.segment_count(), count)
    assert_equal(len(map._sampled_covers), allocated)
    var after = map._sampled_covers[0]
    var before_boxes = _boxes(before)
    var after_boxes = _boxes(after)
    for i in range(4):
        assert_equal(before_boxes[i][0].low, after_boxes[i][0].low)
        assert_equal(before_boxes[i][0].high, after_boxes[i][0].high)
        assert_equal(before_boxes[i][1].low, after_boxes[i][1].low)
        assert_equal(before_boxes[i][1].high, after_boxes[i][1].high)
        assert_equal(before_boxes[i][2].low, after_boxes[i][2].low)
        assert_equal(before_boxes[i][2].high, after_boxes[i][2].high)


def test_nonfinite_high_endpoints_preserve_spent_work() raises:
    var road = _sampled_road(1.0)
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    for high in [inf[DType.float64](), -inf[DType.float64](), quiet_nan]:
        var terms = 7
        assert_false(
            Bool(_sampled_lane_box_cover(road, 0, 0, 0, high, terms, 11))
        )
        assert_equal(terms, 7)
    var terms = 7
    assert_false(
        Bool(_sampled_lane_box_cover(road, 0, 0, quiet_nan, 1, terms, 11))
    )
    assert_equal(terms, 7)


def test_absent_start_geometry_preserves_spent_work() raises:
    var road = _sampled_road(1.0)
    road.info.geometries.clear()
    var terms = 7
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, 11)))
    assert_equal(terms, 7)
    # A nonempty record set can also have no active geometry at low.
    road = _sampled_road(1.0)
    road.info.geometries[0].s = 0.5
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, 11)))
    assert_equal(terms, 7)


def test_nonfinite_sampled_geometry_length_preserves_spent_work() raises:
    var road = _sampled_road(1.0)
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    for length in [inf[DType.float64](), -inf[DType.float64](), quiet_nan]:
        road.info.geometries[0].geometry.length = length
        var terms = 7
        assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, 11)))
        assert_equal(terms, 7)


def test_right_midpoint_collapses_to_middle_after_two_left_cells() raises:
    var road = _sampled_road(1.0)
    var low = bitcast[DType.float64](UInt64(0x3FE0000000000000))
    var high = bitcast[DType.float64](UInt64(0x3FE0000000000003))
    var middle = _midpoint(low, high)
    var first_quarter = _midpoint(low, middle)
    var last_quarter = _midpoint(middle, high)
    # Three equal ULPs: the middle rounds up to the even second neighbor.
    assert_equal(bitcast[DType.uint64](middle), UInt64(0x3FE0000000000002))
    assert_equal(
        bitcast[DType.uint64](first_quarter), UInt64(0x3FE0000000000001)
    )
    assert_true(low < first_quarter)
    assert_true(first_quarter < middle)
    assert_equal(last_quarter, middle)
    assert_true(last_quarter < high)
    var terms = 7
    assert_false(
        Bool(_sampled_lane_box_cover(road, 0, 0, low, high, terms, 11))
    )
    assert_equal(terms, 7)


def test_right_midpoint_collapses_to_high_across_a_binade_boundary() raises:
    var road = _sampled_road(1.0)
    var low = bitcast[DType.float64](UInt64(0x3FDFFFFFFFFFFFFF))
    var high = bitcast[DType.float64](UInt64(0x3FE0000000000002))
    var middle = _midpoint(low, high)
    var first_quarter = _midpoint(low, middle)
    var last_quarter = _midpoint(middle, high)
    # The step below 0.5 is half the step above it. The last tie rounds up.
    assert_equal(bitcast[DType.uint64](middle), UInt64(0x3FE0000000000001))
    assert_equal(
        bitcast[DType.uint64](first_quarter), UInt64(0x3FE0000000000000)
    )
    assert_true(low < first_quarter)
    assert_true(first_quarter < middle)
    assert_true(middle < last_quarter)
    assert_equal(last_quarter, high)
    var terms = 7
    assert_false(
        Bool(_sampled_lane_box_cover(road, 0, 0, low, high, terms, 11))
    )
    assert_equal(terms, 7)


def test_stable_sampled_cells_charge_exactly_one_term_each() raises:
    var road = _sampled_road(1.0)
    # An unrelated later record must not change any cell's selected record.
    var later = _sampled_road(1.0)
    road.info.geometries.append(
        RoadInfoGeometry(2.0, later.info.geometries[0].geometry.copy())
    )
    for kind in [POLY3, PARAM_POLY3]:
        road.info.geometries[0].geometry.kind = kind
        for low in [Float64(0.0), Float64(0.25)]:
            var high = Float64(1.0)
            var middle = _midpoint(low, high)
            var edges: Array[Float64, 5] = [
                low,
                _midpoint(low, middle),
                middle,
                _midpoint(middle, high),
                high,
            ]
            for cell in range(4):
                assert_equal(
                    _reference_work(road, edges[cell], edges[cell + 1]), 1
                )
            var terms = 7
            assert_true(
                Bool(_sampled_lane_box_cover(road, 0, 0, low, high, terms, 11))
            )
            assert_equal(terms, 11)
    # Public record lists can be unsorted. Binary-search outputs still rise
    # monotonically with station: equal outer indices fix all inner ones.
    road = _sampled_road(1.0)
    road.info.geometries[0].s = 0.5
    road.info.geometries[0].geometry.kind = SPIRAL
    road.info.geometries.append(
        RoadInfoGeometry(0.0, later.info.geometries[0].geometry.copy())
    )
    road.info.geometries.append(
        RoadInfoGeometry(2.0, later.info.geometries[0].geometry.copy())
    )
    assert_equal(info_index(road.info.geometries, 0.0), 1)
    assert_equal(info_index(road.info.geometries, 1.0), 1)
    for cell in range(4):
        var low = Float64(cell) / 4.0
        var high = Float64(cell + 1) / 4.0
        assert_equal(info_index(road.info.geometries, low), 1)
        assert_equal(info_index(road.info.geometries, high), 1)
        assert_equal(_reference_work(road, low, high), 1)
    var terms = 7
    assert_true(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, terms, 11)))
    assert_equal(terms, 11)


def test_each_nonfinite_witness_coordinate_keeps_the_candidate() raises:
    var far = _point_box(4.0)
    var cover = _LaneBoxCover(far, far, far, far)
    var query = Vector3(0, 0, 0)
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    var best: Array[Float64, 3] = [1.0, 0.0, 0.0]
    assert_false(_lane_cover_can_improve(cover, query, best))
    for coordinate in range(3):
        for bad in [inf[DType.float64](), -inf[DType.float64](), quiet_nan]:
            var unknown: Array[Float64, 3] = [1.0, 0.0, 0.0]
            unknown[coordinate] = bad
            assert_true(_lane_cover_can_improve(cover, query, unknown))
    assert_false(_lane_cover_can_improve(cover, query, best))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
