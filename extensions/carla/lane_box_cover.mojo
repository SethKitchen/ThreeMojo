# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Optional immutable construction enclosures for sampled lane segments.

Each box encloses a closed quarter-domain of the actual lane evaluator.
The four domains have shared endpoints and cover the complete segment.
They are interval proofs, not a claim based on four sampled points.

Map owns these values with its existing segment/index snapshot. Queries
only read them. As with the cached full-center boxes and R-tree endpoints,
editing source road records after index construction invalidates the
snapshot; this module does not add a mutable cache or a new update API.
"""

from extensions.carla.curve_bounds import _lane_jet, _reference_work
from extensions.carla.lane_value_bounds import _sampled_lane_value_bound
from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import PARAM_POLY3, POLY3
from extensions.carla.lane_refinement import (
    _finite_lane_box,
    _lane_box_can_improve,
    _midpoint,
    _whole_lane_box,
)
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
from std.math import isfinite


@fieldwise_init
struct _LaneBoxCover(ImplicitlyCopyable):
    # Kept only for segments with a complete finite proof. No road, sample
    # table, station partition, witness, or query state is duplicated here.
    var first: Tuple[_Interval, _Interval, _Interval]
    var second: Tuple[_Interval, _Interval, _Interval]
    var third: Tuple[_Interval, _Interval, _Interval]
    var fourth: Tuple[_Interval, _Interval, _Interval]


def _sampled_lane_box_cover(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    mut terms: Int,
    max_terms: Int = 2000000,
) -> Optional[_LaneBoxCover]:
    return _sampled_lane_box_cover_impl[False](
        road, section, lane, low, high, terms, max_terms
    )


def _sampled_lane_box_cover_fast(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    mut terms: Int,
    max_terms: Int = 2000000,
) -> Optional[_LaneBoxCover]:
    return _sampled_lane_box_cover_impl[True](
        road, section, lane, low, high, terms, max_terms
    )


def _sampled_lane_box_cover_impl[
    value_only: Bool
](
    road: Road,
    section: Int,
    lane: Int,
    var low: Float64,
    var high: Float64,
    mut terms: Int,
    max_terms: Int = 2000000,
) -> Optional[_LaneBoxCover]:
    # `terms` is the original chord certificate's spent construction work.
    # Failure is optional: preserve that certificate and all work already
    # spent. In particular, no query/refinement budget is reset or enlarged.
    if not isfinite(low) or not isfinite(high):
        return None
    if high < low:
        var previous = low
        low = high
        high = previous
    if low < 0.0 or not high > low or terms < 0 or terms > max_terms:
        return None
    var at = info_index(road.info.geometries, low)
    if at < 0 or info_index(road.info.geometries, high) != at:
        return None
    ref geometry = road.info.geometries[at].geometry
    if geometry.kind != POLY3 and geometry.kind != PARAM_POLY3:
        return None
    if not isfinite(geometry.length) or not geometry.length > 0.0:
        return None
    if len(geometry.samples) < 2:
        return None
    # Refuse an incomplete four-cell cover at road-s resolution limits.
    # Midpoint avoids overflow and the identical shared endpoints leave no
    # gaps, including the scalar evaluator's sample-selection boundaries.
    var middle = _midpoint(low, high)
    var first_quarter = _midpoint(low, middle)
    var last_quarter = _midpoint(middle, high)
    if not (
        low < first_quarter
        and first_quarter < middle
        and middle < last_quarter
        and last_quarter < high
    ):
        return None
    var edges: Array[Float64, 5] = [
        low,
        first_quarter,
        middle,
        last_quarter,
        high,
    ]
    var boxes: Array[Tuple[_Interval, _Interval, _Interval], 4] = [
        _whole_lane_box(),
        _whole_lane_box(),
        _whole_lane_box(),
        _whole_lane_box(),
    ]
    var i = 0
    while i < 4:
        var work = _reference_work(road, edges[i], edges[i + 1])
        # The enclosing domain selected one stable non-SPIRAL record.
        # Each ordered cell selects that same record, so work is exactly 1.
        if work > max_terms - terms:
            return None
        # Reserve before evaluation, including one that produces no proof.
        terms += work
        try:
            comptime if value_only:
                var point = _sampled_lane_value_bound(
                    road, section, lane, edges[i], edges[i + 1]
                )
                boxes[i] = (
                    point[0].rounded_value(),
                    -point[1].rounded_value(),
                    point[2].rounded_value(),
                )
            else:
                var point = _lane_jet(
                    road, section, lane, edges[i], edges[i + 1]
                )
                boxes[i] = (
                    point[0].rounded_value(),
                    -point[1].rounded_value(),
                    point[2].rounded_value(),
                )
        except:
            # Optional proof failure must not turn a successful original
            # index construction into a new failure.
            return None
        if not _finite_lane_box(boxes[i]):
            return None
        i += 1
    return _LaneBoxCover(boxes[0], boxes[1], boxes[2], boxes[3])


def _lane_cover_can_improve(
    cover: _LaneBoxCover, location: Vector3, best_point: Array[Float64, 3]
) raises -> Bool:
    var i = 0
    while i < 3:
        if not isfinite(best_point[i]):
            return True
        i += 1
    # Defensive unknowns and equality retain the candidate. The existing
    # predicate compares each downward lower with an upward witness upper;
    # only four strict exclusions prove exclusion of the complete segment.
    if (
        not _finite_lane_box(cover.first)
        or not _finite_lane_box(cover.second)
        or not _finite_lane_box(cover.third)
        or not _finite_lane_box(cover.fourth)
    ):
        return True
    return (
        _lane_box_can_improve(cover.first, location, best_point)
        or _lane_box_can_improve(cover.second, location, best_point)
        or _lane_box_can_improve(cover.third, location, best_point)
        or _lane_box_can_improve(cover.fourth, location, best_point)
    )
