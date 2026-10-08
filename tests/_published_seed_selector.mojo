# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Published b96 certified selector, with a test-only target-resume counter.

The body is copied from b96ba07 and only renamed, made a free function,
and extended with the counter. Production scalar and refinement helpers
remain shared so the first-pass comparison uses identical evaluator words.
"""

from extensions.carla.map import Map, Waypoint, _LaneTypeFilter
from extensions.carla.map_search import _MapQueryWork
from extensions.carla.curve_sum2 import _require_sum2_environment
from extensions.carla.curve_distance import _finite_point, _wide_point_order
from extensions.carla.lane_distance import _wide_distance_upper
from extensions.carla.lane_box_cover import _lane_cover_can_improve
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _indexed_curve_lower,
    _lane_box_can_improve,
    _lane_certificate_dominates,
    _lane_certificate_dominates_cells,
    _next_resume_gap,
    _LaneExclusionGoal,
)
from extensions.carla.rtree import _segment_distance2
from extensions.carla.road_info import LaneType
from math.vector3 import Vector3
from std.math import inf


def _published_first_pass_with_work(
    map: Map, location: Vector3, lane_type: LaneType, mut work: _MapQueryWork
) raises -> Optional[Tuple[Waypoint, _LaneCertificate, Int]]:
    work.validate()
    var goal_calls = 0
    if not lane_type.is_valid():
        raise Error("Lane type is not valid")
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    _finite_point(query)
    _require_sum2_environment()
    var indices = List[Int]()
    var certificates = List[_LaneCertificate]()
    var waypoints = List[Waypoint]()
    var accurate = List[Bool]()
    var best = -1
    var frontier = map._tree._nearest_begin(location, work)
    var best_radius = Float64(0.0)
    while True:
        var candidate = map._tree._nearest_next(
            location, _LaneTypeFilter(lane_type.value), frontier, work
        )
        if not candidate:
            break
        var index = candidate.value().start_value
        ref segment = map._segments[index]
        if best >= 0:
            var lower = _indexed_curve_lower(
                _segment_distance2(segment.start, segment.end, location),
                map._curve_deviation,
            )
            if lower > best_radius:
                break
            if not _lane_box_can_improve(
                segment.bounds, location, certificates[best].point
            ):
                continue
            if segment.cover_index >= 0:
                if not _lane_cover_can_improve(
                    map._sampled_covers[segment.cover_index],
                    location,
                    certificates[best].point,
                ):
                    continue
        # Candidate storage is admitted before refinement or any append.
        work.candidate()
        var result = map._nearest_on_segment_certificate(
            index, location, work, seed_only=True
        )
        var improves = best < 0
        if best >= 0:
            var order = _wide_point_order(
                result[1].point, certificates[best].point, query
            )
            improves = order < 0 or (order == 0 and index < indices[best])
        if improves:
            best = len(indices)
            best_radius = _wide_distance_upper(result[1].point, query)
        work._step(len(result[1].cells) + 1)
        indices.append(index)
        waypoints.append(result[0])
        certificates.append(result[1].copy())
        accurate.append(result[1].exact_witness)
    if best < 0:
        return None
    # Admission's strict full-domain exclusions remain valid
    # as these retained candidates improve their stored incumbents.
    var requested_gaps = List[Float64]()
    var requested_scales = List[Float64]()
    for certificate in certificates:
        work._step(2)
        requested_gaps.append(inf[DType.float64]())
        requested_scales.append(certificate.scale)
    while True:
        # A resumed candidate can change the best stored sample. Recheck
        # all index-sensitive dominance relations after every refinement.
        for i in range(len(indices)):
            work._step()
            var order = _wide_point_order(
                certificates[i].point, certificates[best].point, query
            )
            if order < 0 or (order == 0 and indices[i] < indices[best]):
                best = i
        if not accurate[best]:
            # A seed or goal-closed candidate is not an accurate result.
            # Finish the current winner under the original local accuracy
            # and the same cumulative counters before selecting a pose.
            map._resume_on_segment_certificate(
                indices[best],
                location,
                certificates[best],
                None,
                certificates[best].scale,
                work,
            )
            accurate[best] = True
            waypoints[best].s = certificates[best].s
        var target = -1
        for i in range(len(indices)):
            work._step()
            if i == best:
                continue
            if _lane_certificate_dominates(
                certificates[best],
                indices[best],
                certificates[i],
                indices[i],
                query,
            ):
                continue
            # The terminal-aware proof scans the retained cover only
            # after the constant-time bound did not establish dominance.
            work._step(len(certificates[i].cells))
            if _lane_certificate_dominates_cells(
                certificates[best],
                indices[best],
                certificates[i],
                indices[i],
                query,
            ):
                continue
            if (
                certificates[best].exact_witness
                and certificates[i].exact_witness
            ):
                raise Error("Exact lane witnesses have inconsistent dominance")
            target = i
            # Dominance needs a tighter lower bound on the competitor.
            # The current winner contributes an actual scalar witness;
            # proving its own exact minimum is unnecessary here. If the
            # competitor finds a closer witness, the next pass switches
            # the winner and refines this candidate in its new role.
            break
        if target < 0:
            # A valid wide center does not by itself guarantee that the
            # selected public pose is finite and has a valid frame.
            map._validate_query_pose(waypoints[best], work)
            work._step(len(certificates[best].cells))
            return (waypoints[best], certificates[best].copy(), goal_calls)
        var request = _next_resume_gap(
            certificates[target],
            requested_gaps[target],
            requested_scales[target],
        )
        requested_gaps[target] = request
        requested_scales[target] = certificates[target].scale
        goal_calls += 1
        map._resume_on_segment_certificate(
            indices[target],
            location,
            certificates[target],
            request,
            requested_scales[target],
            work,
            _LaneExclusionGoal(
                certificates[best].upper,
                certificates[best].scale,
                indices[best] < indices[target],
            ),
            certificates[best].point.copy(),
        )
        accurate[target] = certificates[target].exact_witness
        waypoints[target].s = certificates[target].s
