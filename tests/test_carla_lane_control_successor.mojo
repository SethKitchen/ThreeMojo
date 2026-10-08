# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Compare a bounded private successor against the unchanged predecessor."""

from extensions.carla.curve_sum2 import _require_sum2_environment
from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.curve_sample_dispatch import _try_sample_dispatch_cuts
from extensions.carla.curve_bounds import (
    _lane_jet,
    _lane_jet_capture,
    _try_lane_envelope_capture,
    _lane_jet_with_proof,
    _lane_width_box,
    _scaled_plan_width_box,
    _reference_work,
    _scaled_point_distance_box,
    _scaled_point_distance_jet,
    _unknown_point,
    _expansion_distance_jet,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_distance import (
    _finite_point,
    _wide_point_order,
)
from extensions.carla.lane_distance import (
    _refinement_square as _normalized_square,
    _point_gap_scale,
    _wide_plan_contains,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _binary_power,
    _next_down,
    _next_up,
)
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
)
from extensions.carla.geometry import ARC, LINE
from extensions.carla.lane_value_bounds import _lane_value_bound
from extensions.carla.curve_rounded_arc import (
    _RoundedArc,
    _RoundedBox,
    _rounded_arc_context,
)
from extensions.carla.curve_frozen_arc import (
    _frozen_arc_context,
    _frozen_arc_center,
    _frozen_arc_expansion,
)
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
from std.math import inf, isfinite, sqrt
from std.memory import bitcast

from extensions.carla.lane_refinement import (
    _legacy_square,
    _checked_center,
    _constant_axis_polynomial,
    _axis_lane_minimum,
    _rounded_axis_lane_minimum,
    _local_seed,
    _midpoint,
    _expansion_center,
    _global_lower,
    _scaled_accuracy,
    _ClosedInterval,
    _rebase_lower,
    _certificate_within_gap,
    _LaneExclusionGoal,
    _goal_excludes,
    _ClosedIntervals,
    _LaneCertificate,
    _exact_lane_certificate,
    _finish_lane_certificate,
    _beats_external_witness,
    _pause_lane_search,
    _rebase_upper,
    _lane_certificate_dominates,
    _lane_certificate_dominates_cells,
    _plan_box_classification,
    _minimizer_plan_width_upper,
    _lane_certificate_contains,
    _refine_lane,
    _refine_lane_certificate,
    _search_accuracy,
    _next_resume_gap,
    _reserve_rounded_arc_box,
    _try_rounded_arc_witness,
    _resume_lane_certificate,
    _continue_lane_certificate,
    _run_lane_search,
    _length_up,
    _whole_lane_box,
    _finite_lane_box,
    _ProofNodeWork,
    _subdivided_lane_box,
    _subdivided_lane_box_with_nodes,
    _chord_error,
    _chord_certificate,
    _chord_certificate_capture,
    _chord_certificate_capture_with_nodes,
    _chord_certificate_impl,
    _chord_certificate_capture_fast,
    _chord_certificate_capture_fast_with_nodes,
    _chord_certificate_impl_with_nodes,
    _admission_roundoff,
    _lane_box_can_improve,
    _indexed_curve_lower,
)
from std.testing import TestSuite, assert_equal, assert_raises
from tests._lazy_taylor_controls import _whole_certificate, _diagonal_road
from tests.test_carla_cross_candidate_certificates import _road
from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.road_info import RoadInfoGeometry


def _reference_expansion_center(
    low: Float64, high: Float64, best: Float64
) -> Float64:
    var center = min(max(best, low), high)
    if center <= low:
        var interior = _next_up(low)
        if interior > low and interior < high:
            return interior
        return _midpoint(low, high)
    if center >= high:
        var interior = _next_down(high)
        if interior > low and interior < high:
            return interior
        return _midpoint(low, high)
    return center


def _reference_run_lane_search(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    mut certificate: _LaneCertificate,
    var pending: List[Tuple[Float64, Float64, Int]],
    var closed: _ClosedIntervals,
    var terminal: List[_ClosedInterval],
    requested_gap: Optional[Tuple[Float64, Float64]],
    max_nodes: Int,
    max_terms: Int,
    max_depth: Int,
    spiral_proof: Optional[_SpiralDomainProof] = None,
    goal: Optional[_LaneExclusionGoal] = None,
    external_witness: Optional[Array[Float64, 3]] = None,
) raises:
    # Fresh and resumed refinement share one solver. Counters and improved
    # incumbents are published immediately, including on an exception.
    # Until success, the older cell cover remains conservative and reusable.
    var entry_lower = certificate.lower
    var entry_scale = certificate.scale
    # Invocation-local only: owner, road snapshot, query and proof are fixed.
    # Exact station/scale words retain branch and normalization identity.
    var sampled_checked = False
    var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None
    var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = None
    var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = None
    var best = certificate.s
    var best_point = certificate.point.copy()
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var frozen: Optional[_RoundedArc] = None
    if (
        len(road.info.geometries) == 1
        and road.info.geometries[0].geometry.kind == ARC
        and max_nodes - certificate.nodes >= 2
        and max_terms - certificate.terms >= 2
    ):
        # Reserve before the optional bounded profile/context traversal.
        # A declined attempt stays charged, including on resumed searches.
        # Leave at least one node and reference term for original work.
        certificate.nodes += 1
        certificate.terms += 1
        frozen = _frozen_arc_context(road, section, lane, low, high)
    while len(pending) > 0 or closed.needs_validation():
        if certificate.nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        certificate.nodes += 1
        if len(pending) == 0:
            # A later winner can reduce width or cross a distance ULP binade.
            # Recheck every tolerance-closed region against the final budget.
            var scale = _point_gap_scale(best_point, query)
            if scale == 0.0:
                certificate = _exact_lane_certificate(
                    best,
                    best_point,
                    query,
                    certificate.nodes,
                    certificate.terms,
                )
                return
            var score = _normalized_square[3](best_point, query, scale)
            var tolerance = _search_accuracy(
                road,
                section,
                lane,
                low,
                high,
                best,
                score.low,
                scale,
                requested_gap,
            )
            var reopened = closed.recheck(scale, score.high, tolerance, goal)
            if Bool(reopened):
                pending.append(reopened.value())
            continue
        var task = pending.pop()
        var lo = task[0]
        var hi = task[1]
        var middle = _midpoint(lo, hi)
        # The root's positive finite station domain has ordered IEEE bits.
        # A tiny cell can be certified by exhaustive actual evaluator calls.
        # Each prepaid leaf handles at most the original three edge-center
        # evaluations and three terminal entries. Every scalar term remains
        # charged. The virtual binary depth preserves original depth limits.
        if lo > 0.0 and isfinite(hi) and hi >= lo:
            var first_bits = bitcast[DType.uint64](lo)
            var last_bits = bitcast[DType.uint64](hi)
            if (
                first_bits >> UInt64(52) == last_bits >> UInt64(52)
                and first_bits >> UInt64(52) > UInt64(0)
                and last_bits - first_bits <= UInt64(32)
            ):
                var span = last_bits - first_bits
                var leaf_depth = 0
                while span > UInt64(1):
                    span = (span + UInt64(1)) // UInt64(2)
                    leaf_depth += 1
                # Unsupported depth falls back to the original evaluation
                # and failure path, preserving its spent-work observations.
                if task[2] <= max_depth - leaf_depth:
                    var bits = first_bits
                    while True:
                        if bits != first_bits and (bits - first_bits) % UInt64(
                            3
                        ) == UInt64(0):
                            if certificate.nodes >= max_nodes:
                                raise Error(
                                    "Lane refinement exhausted its interval"
                                    " work limit"
                                )
                            certificate.nodes += 1
                        var station = bitcast[DType.float64](bits)
                        var point = _checked_center(
                            road,
                            section,
                            lane,
                            station,
                            certificate.terms,
                            max_terms,
                        )
                        var order = _wide_point_order(point, best_point, query)
                        if order < 0:
                            best = station
                            best_point = point.copy()
                            certificate.s = best
                            certificate.point = best_point.copy()
                            closed.reset()
                            terminal.clear()
                            if _beats_external_witness(
                                best_point, query, goal, external_witness
                            ):
                                certificate = _pause_lane_search(
                                    best,
                                    best_point,
                                    query,
                                    closed^,
                                    terminal,
                                    pending,
                                    task,
                                    entry_lower,
                                    entry_scale,
                                    certificate.nodes,
                                    certificate.terms,
                                )
                                return
                        if order <= 0:
                            var point_scale = _point_gap_scale(point, query)
                            if point_scale == 0.0:
                                certificate = _exact_lane_certificate(
                                    best,
                                    best_point,
                                    query,
                                    certificate.nodes,
                                    certificate.terms,
                                )
                                return
                            terminal.append(
                                _ClosedInterval(
                                    station,
                                    station,
                                    task[2] + leaf_depth,
                                    _normalized_square[3](
                                        point, query, point_scale
                                    ).low,
                                    point_scale,
                                )
                            )
                        if bits == last_bits:
                            break
                        bits += UInt64(1)
                    continue
        var sample = middle
        var edge = 0
        while edge < 3:
            if edge == 1:
                sample = lo
            elif edge == 2:
                sample = hi
            var point = _checked_center(
                road, section, lane, sample, certificate.terms, max_terms
            )
            var order = _wide_point_order(point, best_point, query)
            if order < 0:
                best = sample
                best_point = point.copy()
                certificate.s = best
                certificate.point = best_point.copy()
                closed.reset()
                # Every old terminal was compared against the previous
                # incumbent, which this witness strictly improves. All those
                # points are now strict exclusions from the minimizing set.
                terminal.clear()
                if _beats_external_witness(
                    best_point, query, goal, external_witness
                ):
                    certificate = _pause_lane_search(
                        best,
                        best_point,
                        query,
                        closed^,
                        terminal,
                        pending,
                        task,
                        entry_lower,
                        entry_scale,
                        certificate.nodes,
                        certificate.terms,
                    )
                    return
            if (middle <= lo or middle >= hi) and order <= 0:
                var point_scale = _point_gap_scale(point, query)
                if point_scale == 0.0:
                    point_scale = 1.0
                var point_lower = _normalized_square[3](
                    point, query, point_scale
                ).low
                terminal.append(
                    _ClosedInterval(
                        sample, sample, task[2], point_lower, point_scale
                    )
                )
            edge += 1
        var scale = _point_gap_scale(best_point, query)
        if scale == 0.0:
            # Componentwise coincidence establishes the exact global minimum.
            certificate = _exact_lane_certificate(
                best, best_point, query, certificate.nodes, certificate.terms
            )
            return
        if middle <= lo or middle >= hi:
            continue
        var best_bounds = _normalized_square[3](best_point, query, scale)
        var best_upper = best_bounds.high
        var work = _reference_work(road, lo, hi)
        if work >= 0:
            if certificate.terms > max_terms - work:
                raise Error(
                    "Lane refinement exhausted its quadrature work limit"
                )
            certificate.terms += work
            # Evaluate the current cell's full producer. A retained ancestor
            # model can keep a wider error floor and turn a short ordinary
            # continuation into a default-budget failure on valid lane centers.
            var point_domain: Tuple[_Jet, _Jet, _Jet]
            if frozen:
                point_domain = _frozen_arc_center(
                    frozen.value(), lo, hi, Vector3(0, 0, 0)
                )
            else:
                point_domain = _lane_jet_with_proof(
                    road, section, lane, lo, hi, low, high, spiral_proof
                )
            var natural = _scaled_point_distance_box(
                point_domain, location, scale
            ).low
            if natural > best_upper:
                continue
            if _goal_excludes(natural, scale, goal):
                closed.add(_ClosedInterval(lo, hi, task[2], natural, scale))
                continue
            # The natural enclosure is already a global lower bound on this
            # cell. Avoid an optional local seed when the existing witness
            # already satisfies the unchanged gap. Keep the cell so later
            # incumbent/width/binade changes trigger the same revalidation.
            var natural_tolerance = _search_accuracy(
                road,
                section,
                lane,
                low,
                high,
                best,
                best_bounds.low,
                scale,
                requested_gap,
            )
            if _next_up(best_upper - natural) <= natural_tolerance:
                closed.add(_ClosedInterval(lo, hi, task[2], natural, scale))
                continue
            var domain = _scaled_point_distance_jet(
                point_domain, location, scale
            )
            if (
                domain.second.low > 0.0
                and domain.first.contains(0.0)
                and isfinite(hi - lo)
            ):
                var local = _local_seed(
                    road,
                    section,
                    lane,
                    lo,
                    hi,
                    query,
                    best,
                    best_point,
                    certificate.terms,
                    max_terms,
                )
                if local[0] != best:
                    closed.reset()
                    terminal.clear()
                best = local[0]
                best_point = local[1].copy()
                certificate.s = best
                certificate.point = best_point.copy()
                if _beats_external_witness(
                    best_point, query, goal, external_witness
                ):
                    certificate = _pause_lane_search(
                        best,
                        best_point,
                        query,
                        closed^,
                        terminal,
                        pending,
                        task,
                        entry_lower,
                        entry_scale,
                        certificate.nodes,
                        certificate.terms,
                    )
                    return
                scale = _point_gap_scale(best_point, query)
                if scale == 0.0:
                    certificate = _exact_lane_certificate(
                        best,
                        best_point,
                        query,
                        certificate.nodes,
                        certificate.terms,
                    )
                    return
                best_bounds = _normalized_square[3](best_point, query, scale)
                best_upper = best_bounds.high
                # Scale changes invalidate all normalized distance bounds.
                natural = _scaled_point_distance_box(
                    point_domain, location, scale
                ).low
                if natural > best_upper:
                    continue
                if _goal_excludes(natural, scale, goal):
                    closed.add(_ClosedInterval(lo, hi, task[2], natural, scale))
                    continue
                domain = _scaled_point_distance_jet(
                    point_domain, location, scale
                )
            var tolerance = _search_accuracy(
                road,
                section,
                lane,
                low,
                high,
                best,
                best_bounds.low,
                scale,
                requested_gap,
            )
            # A clamped singleton endpoint can have a different jet from
            # the interior branch. Taylor bounds need that same branch.
            var center_s = _expansion_center(lo, hi, best)
            var center_work = _reference_work(road, center_s, center_s)
            if center_work >= 0:
                if certificate.terms > max_terms - center_work:
                    raise Error(
                        "Lane refinement exhausted its quadrature work limit"
                    )
                certificate.terms += center_work
                var fast_center: Optional[_Jet] = None
                # The original full-domain second derivative and scalar
                # error also apply to this ideal moment-backed expansion.
                # Retain headroom for the unchanged translated fallback.
                if (
                    spiral_proof
                    and domain.second.is_finite()
                    and center_work <= max_terms - certificate.terms
                ):
                    var station_word = bitcast[DType.uint64](center_s)
                    var scale_word = bitcast[DType.uint64](scale)
                    if (
                        external_witness
                        and cached_fast
                        and cached_fast.value()[0] == station_word
                        and cached_fast.value()[1] == scale_word
                    ):
                        fast_center = cached_fast.value()[2]
                    else:
                        fast_center = _try_proof_expansion_jet(
                            road,
                            section,
                            lane,
                            center_s,
                            location,
                            scale,
                            low,
                            high,
                            spiral_proof,
                        )
                        if external_witness and fast_center:
                            cached_fast = (
                                station_word,
                                scale_word,
                                fast_center.value(),
                            )
                    if fast_center:
                        var fast_delta = _Interval(lo, hi) - _Interval.point(
                            center_s
                        )
                        var fast_lower = max(
                            natural,
                            _global_lower(
                                domain, fast_center.value(), fast_delta
                            ),
                        )
                        if fast_lower > best_upper:
                            continue
                        if (
                            _goal_excludes(fast_lower, scale, goal)
                            or _next_up(best_upper - fast_lower) <= tolerance
                        ):
                            closed.add(
                                _ClosedInterval(
                                    lo, hi, task[2], fast_lower, scale
                                )
                            )
                            continue
                        # A failed optional attempt is charged before the
                        # original traversal; neither work cap is enlarged.
                        certificate.terms += center_work
                # Only a failed cached proof needs the expensive local GL
                # error traversal. It is still charged before execution.
                if spiral_proof and domain.error > tolerance * 0.25:
                    if certificate.terms > max_terms - work:
                        raise Error(
                            "Lane refinement exhausted its quadrature work"
                            " limit"
                        )
                    certificate.terms += work
                    # Original F is prepaid; the optional model owns its node
                    # and whole-union C. A decline retains all actual debits.
                    var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None
                    # Keep the original closed-cell recheck available after
                    # this optional producer. The original F is already paid.
                    if max_nodes - certificate.nodes >= 2:
                        grouped = _try_grouped_lane_jet(
                            road,
                            section,
                            lane,
                            lo,
                            hi,
                            certificate.nodes,
                            certificate.terms,
                            max_nodes,
                            max_terms,
                        )
                    if grouped:
                        point_domain = grouped.value()
                    else:
                        point_domain = _lane_jet(road, section, lane, lo, hi)
                    natural = max(
                        natural,
                        _scaled_point_distance_box(
                            point_domain, location, scale
                        ).low,
                    )
                    if natural > best_upper:
                        continue
                    if _goal_excludes(natural, scale, goal):
                        closed.add(
                            _ClosedInterval(lo, hi, task[2], natural, scale)
                        )
                        continue
                    domain = _scaled_point_distance_jet(
                        point_domain, location, scale
                    )
                    if fast_center:
                        var tightened_delta = _Interval(
                            lo, hi
                        ) - _Interval.point(center_s)
                        var tightened_lower = max(
                            natural,
                            _global_lower(
                                domain, fast_center.value(), tightened_delta
                            ),
                        )
                        if tightened_lower > best_upper:
                            continue
                        if (
                            _goal_excludes(tightened_lower, scale, goal)
                            or _next_up(best_upper - tightened_lower)
                            <= tolerance
                        ):
                            closed.add(
                                _ClosedInterval(
                                    lo, hi, task[2], tightened_lower, scale
                                )
                            )
                            continue
                # A nonfinite second derivative makes _global_lower ignore
                # its expansion argument. A finite rounded domain value also
                # establishes that this is an evaluated expression enclosure,
                # rather than an unvalidated whole/unknown record domain.
                # Retain the original work reservation above. Only skip the
                # unused traversal; no bound, tolerance, or cap changes.
                var center = _Jet.constant(0.0)
                if (
                    domain.second.is_finite()
                    or not domain.rounded_value().is_finite()
                ):
                    var station_word = bitcast[DType.uint64](center_s)
                    var scale_word = bitcast[DType.uint64](scale)
                    if (
                        external_witness
                        and cached_expansion
                        and cached_expansion.value()[0] == station_word
                        and cached_expansion.value()[1] == scale_word
                    ):
                        center = cached_expansion.value()[2]
                    else:
                        if frozen:
                            center = _frozen_arc_expansion(
                                frozen.value(), center_s, location, scale
                            )
                        else:
                            center = _expansion_distance_jet(
                                road, section, lane, center_s, location, scale
                            )
                        if external_witness:
                            cached_expansion = (
                                station_word,
                                scale_word,
                                center,
                            )
                var delta = _Interval(lo, hi) - _Interval.point(center_s)
                var lower = max(natural, _global_lower(domain, center, delta))
                var support = _Interval(lo, hi)
                if external_witness:
                    support = _minimizer_support(
                        domain, center, center_s, best, lo, hi
                    )
                if lower > best_upper:
                    continue
                if (
                    _goal_excludes(lower, scale, goal)
                    or _next_up(best_upper - lower) <= tolerance
                ):
                    closed.add(
                        _ClosedInterval(
                            support.low, support.high, task[2], lower, scale
                        )
                    )
                    continue
                if support.low > lo or support.high < hi:
                    if task[2] >= max_depth:
                        raise Error(
                            "Lane refinement exhausted its numerical accuracy"
                            " limit"
                        )
                    pending.append((support.low, support.high, task[2] + 1))
                    continue
        if task[2] >= max_depth:
            raise Error(
                "Lane refinement exhausted its numerical accuracy limit"
            )
        # The unchanged node has now exhausted its witness/closure choices.
        # Keep each source owner unchanged while isolating the exact stored
        # sample-dispatch transition. Adjacent words leave no station gap.
        # Declined setup or unavailable depth retains the original path.
        if not sampled_checked and task[2] < max_depth:
            sampled_checked = True
            sampled_cuts = _try_sample_dispatch_cuts(
                road,
                low,
                high,
                certificate.nodes,
                certificate.terms,
                max_nodes,
                max_terms,
            )
        if sampled_cuts and task[2] < max_depth:
            var split_at = 0.0
            if lo < sampled_cuts.value()[0] and sampled_cuts.value()[0] <= hi:
                split_at = sampled_cuts.value()[0]
            elif (
                sampled_cuts.value()[2] == 2
                and lo < sampled_cuts.value()[1]
                and sampled_cuts.value()[1] <= hi
            ):
                split_at = sampled_cuts.value()[1]
            if split_at > 0.0:
                var before = bitcast[DType.float64](
                    bitcast[DType.uint64](split_at) - UInt64(1)
                )
                if before >= lo:
                    if external_witness and best >= split_at:
                        pending.append((lo, before, task[2] + 1))
                        pending.append((split_at, hi, task[2] + 1))
                    else:
                        pending.append((split_at, hi, task[2] + 1))
                        pending.append((lo, before, task[2] + 1))
                    continue
        if external_witness and best >= middle:
            pending.append((lo, middle, task[2] + 1))
            pending.append((middle, hi, task[2] + 1))
        else:
            pending.append((middle, hi, task[2] + 1))
            pending.append((lo, middle, task[2] + 1))
    # Return only after every pending/reopened cell is covered. Goal-closed
    # cells remain valid minimum bounds, but do not imply ordinary accuracy.
    certificate = _finish_lane_certificate(
        best,
        best_point,
        query,
        closed,
        terminal,
        certificate.nodes,
        certificate.terms,
    )


def test_expansion_center_ordered_finite_boundary_words() raises:
    var words: List[UInt64] = [
        0,
        1,
        2,
        0x000FFFFFFFFFFFFF,
        0x0010000000000000,
        0x3FEFFFFFFFFFFFFF,
        0x3FF0000000000000,
        0x3FF0000000000001,
        0x7FEFFFFFFFFFFFFE,
        0x7FEFFFFFFFFFFFFF,
    ]
    for i in range(len(words)):
        for j in range(i, len(words)):
            var low = bitcast[DType.float64](words[i])
            var high = bitcast[DType.float64](words[j])
            for best in [low, high, _midpoint(low, high)]:
                assert_equal(
                    bitcast[DType.uint64](_expansion_center(low, high, best)),
                    bitcast[DType.uint64](
                        _reference_expansion_center(low, high, best)
                    ),
                )
                assert_equal(
                    bitcast[DType.uint64](
                        _expansion_center(-high, -low, -best)
                    ),
                    bitcast[DType.uint64](
                        _reference_expansion_center(-high, -low, -best)
                    ),
                )


def _case[
    reference: Bool
](first_cell: Int, depth: Int) raises -> _LaneCertificate:
    var road = _road()
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 3.0)
    for i in range(4):
        var x = Float64(-1.0 if i % 2 == 0 else 1.0)
        geometry.samples.append(_Sample(x, 0.0, Float64(i), 1.0, 0.0))
    road.length = 3.0
    road.info.geometries[0] = RoadInfoGeometry(0.0, geometry^)
    var location = Vector3(0, 1, 0)
    var pending = List[Tuple[Float64, Float64, Int]]()
    var seed = Float64(0.5)
    if first_cell == 0:
        pending.append((0.1, 2.9, 0))
    elif first_cell == 1:
        pending.append((0.1, 1.1, 0))
        pending.append((1.1, 2.9, 0))
        seed = 1.5
    else:
        pending.append((0.1, 2.1, 0))
        pending.append((2.1, 2.9, 0))
        seed = 2.5
    var certificate = _whole_certificate(road, location, 0.1, 2.9, seed)
    with assert_raises(contains="numerical accuracy limit"):
        if reference:
            _reference_run_lane_search(
                road,
                0,
                0,
                0.1,
                2.9,
                location,
                certificate,
                pending^,
                _ClosedIntervals(),
                List[_ClosedInterval](),
                (Float64(0.0), Float64(1.0)),
                100,
                10000,
                depth,
            )
        else:
            _run_lane_search(
                road,
                0,
                0,
                0.1,
                2.9,
                location,
                certificate,
                pending^,
                _ClosedIntervals(),
                List[_ClosedInterval](),
                (Float64(0.0), Float64(1.0)),
                100,
                10000,
                depth,
            )
    return certificate^


def test_dispatch_preserves_exact_work_witness_cells_and_depth_refusal() raises:
    for depth in [0, 1, 3]:
        for first_cell in range(3):
            var before = _case[True](first_cell, depth)
            var after = _case[False](first_cell, depth)
            assert_equal(before.nodes, after.nodes)
            assert_equal(before.terms, after.terms)
            assert_equal(before.s, after.s)
            assert_equal(before.scale, after.scale)
            assert_equal(before.lower, after.lower)
            assert_equal(before.upper, after.upper)
            assert_equal(before.exact_witness, after.exact_witness)
            for axis in range(3):
                assert_equal(before.point[axis], after.point[axis])
            assert_equal(len(before.cells), len(after.cells))
            for i in range(len(before.cells)):
                assert_equal(before.cells[i].low, after.cells[i].low)
                assert_equal(before.cells[i].high, after.cells[i].high)
                assert_equal(before.cells[i].depth, after.cells[i].depth)
                assert_equal(before.cells[i].lower, after.cells[i].lower)
                assert_equal(before.cells[i].scale, after.cells[i].scale)


def test_unavailable_dispatch_retains_original_work_and_refusal() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var before = _whole_certificate(road, location, 0.4, 0.7, 0.4)
    var after = before.copy()
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.4, 0.7, 0)]
    with assert_raises(contains="numerical accuracy limit"):
        _reference_run_lane_search(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            before,
            pending.copy(),
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            10000,
            1,
        )
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            after,
            pending.copy(),
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            10000,
            1,
        )
    assert_equal(before.nodes, after.nodes)
    assert_equal(before.terms, after.terms)
    assert_equal(before.s, after.s)
    assert_equal(before.lower, after.lower)
    assert_equal(before.upper, after.upper)
    assert_equal(before.exact_witness, after.exact_witness)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
