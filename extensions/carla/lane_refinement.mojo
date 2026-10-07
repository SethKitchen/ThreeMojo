# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite global refinement and admission certificates for lane curves.

The numerical expressions live in curve_bounds. This module owns finite
local work and accuracy limits. An unresolved interval raises an Error. It
never reports an off-road result or a partially searched minimum.
"""

from extensions.carla.curve_sum2 import _require_sum2_environment
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


def _legacy_square(
    point: Array[Float64, 3], query: Array[Float64, 3]
) -> Float64:
    # Retained private return value only. Search order and certificates never
    # use this unscaled square, which may underflow or overflow.
    var x = point[0] - query[0]
    var y = point[1] - query[1]
    var z = point[2] - query[2]
    return x * x + y * y + z * z


# One compiled scalar graph binds stored-center witnesses across query sites.
# Interval bounds retain the allowed contraction errors inside this graph.
@no_inline
def _checked_center(
    road: Road,
    section: Int,
    lane: Int,
    s: Float64,
    mut terms: Int,
    max_terms: Int,
) raises -> Array[Float64, 3]:
    var work = _reference_work(road, s, s)
    if work < 0:
        raise Error("Lane refinement cannot resolve the quadrature count")
    if terms > max_terms - work:
        raise Error("Lane refinement exhausted its quadrature work limit")
    terms += work
    var center = road._lane_center(section, lane, s)
    _finite_point(center)
    return center^


def _constant_axis_polynomial(polynomial: CubicPolynomial) -> Bool:
    return polynomial.b == 0.0 and polynomial.c == 0.0 and polynomial.d == 0.0


def _axis_lane_minimum(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
) raises -> Optional[Tuple[Float64, Float64, Array[Float64, 3], Int, Int]]:
    # A zero-heading LINE with constant lateral and vertical coordinates has
    # a monotone stored x evaluator, including subtraction, clamp, and rounding.
    # This is an exact stored-point minimum, not an affine projection heuristic.
    # Return s, the legacy square, the exact minimum witness, nodes, and terms.
    # Plateau s selection follows this deterministic search: endpoint, inverse
    # hit, then bit midpoint; a final equal bracket keeps its lower s. It does
    # not promise the first s on a plateau or alter segment-index tie ordering.
    if not (isfinite(low) and isfinite(high)) or low < 0.0 or high < low:
        raise Error(
            "Axis lane search needs finite nonnegative parameter bounds"
        )
    road._check_lane(section, lane)
    if len(road.info.geometries) != 1:
        return None
    ref record = road.info.geometries[0]
    if record.geometry.kind != LINE or record.geometry.heading != 0.0:
        return None
    if len(road.info.lane_offsets) != 1 or len(road.info.elevations) != 1:
        return None
    if not _constant_axis_polynomial(road.info.lane_offsets[0].polynomial):
        return None
    if not _constant_axis_polynomial(road.info.elevations[0].polynomial):
        return None
    # Conservatively check both sides. Every accumulated width is constant;
    # other sections and records still use their existing evaluator branches.
    for current in road.sections[section].lanes:
        if current.id.value == 0:
            continue
        if len(current.info.widths) != 1:
            return None
        if not _constant_axis_polynomial(current.info.widths[0].polynomial):
            return None
    if max_nodes <= 0:
        raise Error("Lane refinement exhausted its interval work limit")
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    _finite_point(query)
    var terms = 0
    var nodes = 1
    var depth = 0
    # Normalize negative zero before using nonnegative Float64 bit order.
    var lo = Float64(0.0) if low == 0.0 else low
    var hi = high
    var left = _checked_center(road, section, lane, lo, terms, max_terms)
    var right = _checked_center(road, section, lane, hi, terms, max_terms)
    if query[0] <= left[0] or lo == hi:
        return (lo, _legacy_square(left, query), left^, nodes, terms)
    if query[0] >= right[0]:
        return (hi, _legacy_square(right, query), right^, nodes, terms)
    # An inverse is only a seed. Accept it only after the actual evaluator
    # proves zero x residual, the exact lower bound with fixed y and z.
    var seed = (query[0] - record.geometry.x) + record.s
    if isfinite(seed):
        seed = min(max(seed, lo), hi)
        var point = _checked_center(road, section, lane, seed, terms, max_terms)
        if point[0] == query[0]:
            return (seed, _legacy_square(point, query), point^, nodes, terms)
        if point[0] < query[0]:
            lo = seed
            left = point^
        else:
            hi = seed
            right = point^
    var lo_bits = bitcast[DType.uint64](lo)
    var hi_bits = bitcast[DType.uint64](hi)
    # The finite nonnegative bit domain has fewer than 2^63 members. Thus
    # at most 63 bisections leave adjacent parameters. Count every evaluation
    # through _checked_center and every split against the original limits.
    while hi_bits - lo_bits > UInt64(1):
        if nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        if depth >= max_depth:
            raise Error(
                "Lane refinement exhausted its numerical accuracy limit"
            )
        nodes += 1
        depth += 1
        var middle_bits = lo_bits + (hi_bits - lo_bits) // UInt64(2)
        var middle = bitcast[DType.float64](middle_bits)
        var point = _checked_center(
            road, section, lane, middle, terms, max_terms
        )
        if point[0] == query[0]:
            return (middle, _legacy_square(point, query), point^, nodes, terms)
        if point[0] < query[0]:
            lo_bits = middle_bits
            lo = middle
            left = point^
        else:
            hi_bits = middle_bits
            hi = middle
            right = point^
    # All parameters outside this bracket have a no-smaller x residual.
    # The two stored full distances can differ by less than a rounded ULP.
    if _wide_point_order(right, left, query) < 0:
        return (hi, _legacy_square(right, query), right^, nodes, terms)
    return (lo, _legacy_square(left, query), left^, nodes, terms)


def _rounded_axis_lane_minimum(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    mut nodes: Int,
    mut terms: Int,
    max_nodes: Int,
    max_terms: Int,
    max_depth: Int,
) raises -> Optional[Tuple[Float64, Float64, Array[Float64, 3], Int, Int]]:
    # The old axis eligibility scan is already charged by the map. This
    # optional context has its own node and reference term, including when
    # it declines. Pass those counters into ordinary fallback unchanged.
    if len(road.info.geometries) != 1:
        return None
    if road.info.geometries[0].geometry.kind != LINE:
        return None
    if nodes >= max_nodes:
        raise Error("Lane refinement exhausted its interval work limit")
    nodes += 1
    if terms > max_terms - 1:
        raise Error("Lane refinement exhausted its quadrature work limit")
    terms += 1
    var context = _rounded_line_axis_context(road, section, lane, low, high)
    if not context:
        return None
    # Reserve the search root separately from the optional proof node.
    if nodes >= max_nodes:
        raise Error("Lane refinement exhausted its interval work limit")
    nodes += 1
    var depth = 0
    var model = context.value()
    var axis = model.axis
    var direction = Float64(1.0 if model.slope > 0.0 else -1.0)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    _finite_point(query)
    var lo = Float64(0.0) if low == 0.0 else low
    var hi = high
    var left = _checked_center(road, section, lane, lo, terms, max_terms)
    var right = _checked_center(road, section, lane, hi, terms, max_terms)
    var target = direction * query[axis]
    if target <= direction * left[axis] or lo == hi:
        return (lo, _legacy_square(left, query), left^, nodes, terms)
    if target >= direction * right[axis]:
        return (hi, _legacy_square(right, query), right^, nodes, terms)
    # An inverse is a seed only. A hit of the actual stored coordinate is
    # the exact minimum because the proof fixes both other coordinates.
    var seed = lo + (query[axis] - left[axis]) / model.slope
    if isfinite(seed):
        seed = min(max(seed, lo), hi)
        var point = _checked_center(road, section, lane, seed, terms, max_terms)
        if point[axis] == query[axis]:
            return (seed, _legacy_square(point, query), point^, nodes, terms)
        if direction * point[axis] < target:
            lo = seed
            left = point^
        else:
            hi = seed
            right = point^
    var lo_bits = bitcast[DType.uint64](lo)
    var hi_bits = bitcast[DType.uint64](hi)
    while hi_bits - lo_bits > UInt64(1):
        if nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        if depth >= max_depth:
            raise Error(
                "Lane refinement exhausted its numerical accuracy limit"
            )
        nodes += 1
        depth += 1
        var middle_bits = lo_bits + (hi_bits - lo_bits) // UInt64(2)
        var middle = bitcast[DType.float64](middle_bits)
        var point = _checked_center(
            road, section, lane, middle, terms, max_terms
        )
        if point[axis] == query[axis]:
            return (middle, _legacy_square(point, query), point^, nodes, terms)
        if direction * point[axis] < target:
            lo_bits = middle_bits
            lo = middle
            left = point^
        else:
            hi_bits = middle_bits
            hi = middle
            right = point^
    # Parameters outside the adjacent bracket have no smaller axis residual.
    # Compare full distances exactly and keep the lower s on an exact tie.
    if _wide_point_order(right, left, query) < 0:
        return (hi, _legacy_square(right, query), right^, nodes, terms)
    return (lo, _legacy_square(left, query), left^, nodes, terms)


def _local_seed(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    query: Array[Float64, 3],
    best: Float64,
    best_point: Array[Float64, 3],
    mut terms: Int,
    max_terms: Int,
) raises -> Tuple[Float64, Array[Float64, 3]]:
    comptime ratio = Float64(0.6180339887498948482)
    var lo = low
    var hi = high
    var one = hi - ratio * (hi - lo)
    var two = lo + ratio * (hi - lo)
    var p1 = _checked_center(road, section, lane, one, terms, max_terms)
    var p2 = _checked_center(road, section, lane, two, terms, max_terms)
    var steps = 0
    while steps < 40:
        steps += 1
        if _wide_point_order(p1, p2, query) <= 0:
            hi = two
            two = one
            p2 = p1^
            one = hi - ratio * (hi - lo)
            p1 = _checked_center(road, section, lane, one, terms, max_terms)
        else:
            lo = one
            one = two
            p1 = p2^
            two = lo + ratio * (hi - lo)
            p2 = _checked_center(road, section, lane, two, terms, max_terms)
    var result = best
    var point = best_point.copy()
    if _wide_point_order(p1, point, query) < 0:
        result = one
        point = p1^
    if _wide_point_order(p2, point, query) < 0:
        result = two
        point = p2^
    return (result, point^)


def _midpoint(low: Float64, high: Float64) -> Float64:
    var span = high - low
    if not isfinite(span):
        return low * 0.5 + high * 0.5
    return low + span * 0.5


def _expansion_center(low: Float64, high: Float64, best: Float64) -> Float64:
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


def _global_lower(domain: _Jet, center: _Jet, delta: _Interval) -> Float64:
    var natural = domain.rounded_value().low
    if not domain.second.is_finite() or not center.first.is_finite():
        return max(0.0, natural)
    # Taylor's theorem for the actual stored polynomial/rational expression.
    # The separately propagated scalar evaluation error remains in the bound.
    var taylor = (
        center.value
        + center.first * delta
        + (_Interval.point(0.5) * domain.second * delta.square())
    )
    var lower = max(natural, _next_down(taylor.low - domain.error))
    if domain.second.low > 0.0:
        # Strong convexity supplies a global lower bound from any center.
        # This uses the polynomial derivative, not ideal trig identities.
        var correction = center.first.square() / (
            _Interval.point(2.0) * _Interval.point(domain.second.low)
        )
        var convex = center.value - correction
        lower = max(lower, _next_down(convex.low - domain.error))
    return max(0.0, lower)


def _scaled_accuracy(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    best: Float64,
    best_lower: Float64,
    scale: Float64,
) raises -> Float64:
    # The spatial target is unchanged. Division precedes the square.
    var spatial_scale = high - low
    var width = abs(road.lane_width(section, lane, best))
    if width > 0.0:
        spatial_scale = min(spatial_scale, width)
    var spatial = (
        _Interval.point(spatial_scale)
        / _Interval.point(scale)
        * _Interval.point(0.00000095367431640625)
    )
    # The scale is a power of two. Take the ULP at a lower enclosure of
    # the current score, never at an inflated upper bound. This retains or
    # tightens the former 64-ULP rule when converted to world squared units.
    var rounding = _Interval.point(64.0) * _Interval.point(
        _next_up(best_lower) - best_lower
    )
    # Consume only a lower enclosure of the ideal allowance. Directed
    # normalization must not enlarge the existing acceptance budget.
    return max(0.0, (spatial.square() + rounding).low)


@fieldwise_init
struct _ClosedInterval(ImplicitlyCopyable):
    var low: Float64
    var high: Float64
    var depth: Int
    var lower: Float64
    var scale: Float64


def _rebase_lower(
    lower: Float64, old_scale: Float64, scale: Float64
) -> Float64:
    if old_scale == scale:
        return lower
    var ratio = _Interval.point(old_scale) / _Interval.point(scale)
    return max(0.0, (_Interval.point(lower) * ratio.square()).low)


def _certificate_within_gap(
    lower: Float64,
    old_scale: Float64,
    scale: Float64,
    upper: Float64,
    tolerance: Float64,
) -> Bool:
    return _next_up(upper - _rebase_lower(lower, old_scale, scale)) <= tolerance


@fieldwise_init
struct _LaneExclusionGoal(ImplicitlyCopyable):
    # A checked scalar witness from another original segment. This upper
    # bound is a selection goal, never an accuracy allowance for this lane.
    var upper: Float64
    var scale: Float64
    var allow_equal: Bool


def _goal_excludes(
    lower: Float64,
    scale: Float64,
    goal: Optional[_LaneExclusionGoal],
) -> Bool:
    if not goal:
        return False
    var target = goal.value()
    var common = max(scale, target.scale)
    var bound = _rebase_lower(lower, scale, common)
    var upper = _rebase_upper(target.upper, target.scale, common)
    if target.allow_equal:
        return upper <= bound
    return upper < bound


struct _ClosedIntervals(Copyable, Movable):
    var values: List[_ClosedInterval]
    var validated: Int

    def __init__(out self):
        self.values = List[_ClosedInterval]()
        self.validated = 0

    def reset(mut self):
        self.validated = 0

    def add(mut self, interval: _ClosedInterval):
        self.values.append(interval)

    def needs_validation(self) -> Bool:
        return self.validated < len(self.values)

    def recheck(
        mut self,
        scale: Float64,
        upper: Float64,
        tolerance: Float64,
        goal: Optional[_LaneExclusionGoal] = None,
    ) -> Optional[Tuple[Float64, Float64, Int]]:
        # The caller first checks needs_validation. Swap-pop removes only
        # this unvalidated item, so the validated prefix remains intact.
        var certificate = self.values[self.validated]
        if _goal_excludes(
            certificate.lower, certificate.scale, goal
        ) or _certificate_within_gap(
            certificate.lower, certificate.scale, scale, upper, tolerance
        ):
            self.validated += 1
            return None
        self.values[self.validated] = self.values[len(self.values) - 1]
        _ = self.values.pop()
        return (certificate.low, certificate.high, certificate.depth)


@fieldwise_init
struct _LaneCertificate(Copyable, Movable):
    # Bounds enclose the candidate's exact minimum stored-point square in
    # units of scale^2. A returned sample alone is never a minimum proof.
    var s: Float64
    var point: Array[Float64, 3]
    var scale: Float64
    var lower: Float64
    var upper: Float64
    var exact_witness: Bool
    var cells: List[_ClosedInterval]
    var nodes: Int
    var terms: Int


def _exact_lane_certificate(
    s: Float64,
    point: Array[Float64, 3],
    query: Array[Float64, 3],
    nodes: Int,
    terms: Int,
) raises -> _LaneCertificate:
    var scale = _point_gap_scale(point, query)
    if scale == 0.0:
        scale = 1.0
    var score = _normalized_square[3](point, query, scale)
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(s, s, 0, score.low, scale)
    ]
    return _LaneCertificate(
        s,
        point.copy(),
        scale,
        score.low,
        score.high,
        True,
        cells^,
        nodes,
        terms,
    )


def _finish_lane_certificate(
    best: Float64,
    point: Array[Float64, 3],
    query: Array[Float64, 3],
    closed: _ClosedIntervals,
    terminal: List[_ClosedInterval],
    nodes: Int,
    terms: Int,
) raises -> _LaneCertificate:
    var scale = _point_gap_scale(point, query)
    if scale == 0.0:
        return _exact_lane_certificate(best, point, query, nodes, terms)
    var score = _normalized_square[3](point, query, scale)
    var lower = score.high
    var all_resolved = True
    var cells = List[_ClosedInterval]()
    # Hard exclusions stay excluded after an incumbent improvement. Keep
    # every other possible minimizer, including evaluated adjacent Floats.
    for cell in closed.values:
        var bound = _rebase_lower(cell.lower, cell.scale, scale)
        if bound <= score.high:
            lower = min(lower, bound)
            all_resolved = all_resolved and (
                cell.low == cell.high or bound >= score.high
            )
            cells.append(cell)
    for cell in terminal:
        var bound = _rebase_lower(cell.lower, cell.scale, scale)
        if bound <= score.high:
            lower = min(lower, bound)
            all_resolved = all_resolved and (
                cell.low == cell.high or bound >= score.high
            )
            cells.append(cell)
    if len(cells) == 0:
        raise Error("Lane certificate lost its possible minimizing cells")
    # Each terminal point was already compared with this incumbent exactly.
    # A complete nonterminal cell whose lower bound reaches the witness
    # upper also proves that no point there can strictly improve it. Keeping
    # such cells is essential for ties; splitting them cannot improve proof
    # of this incumbent. No earliest-parameter choice is implied.
    return _LaneCertificate(
        best,
        point.copy(),
        scale,
        lower,
        score.high,
        all_resolved,
        cells^,
        nodes,
        terms,
    )


def _rebase_upper(
    upper: Float64, old_scale: Float64, scale: Float64
) -> Float64:
    if old_scale == scale:
        return upper
    var ratio = _Interval.point(old_scale) / _Interval.point(scale)
    return max(0.0, (_Interval.point(upper) * ratio.square()).high)


def _lane_certificate_dominates(
    one: _LaneCertificate,
    one_index: Int,
    two: _LaneCertificate,
    two_index: Int,
    query: Array[Float64, 3],
) raises -> Bool:
    if one.exact_witness and two.exact_witness:
        var order = _wide_point_order(one.point, two.point, query)
        return order < 0 or (order == 0 and one_index < two_index)
    var scale = max(one.scale, two.scale)
    var upper = _rebase_upper(one.upper, one.scale, scale)
    var lower = _rebase_lower(two.lower, two.scale, scale)
    # A later candidate may tie. An earlier candidate wins any exact tie.
    if one_index < two_index:
        return upper <= lower
    return upper < lower


def _lane_certificate_dominates_cells(
    one: _LaneCertificate,
    one_index: Int,
    two: _LaneCertificate,
    two_index: Int,
    query: Array[Float64, 3],
) raises -> Bool:
    # Every terminal point was exactly compared with two.point by the
    # producer. Later incumbent improvements only strengthen that ordering.
    # One's WITNESS can therefore bound those points without asking a rounded
    # lower score to distinguish sub-ULP exact distances or requiring one to
    # be an exact minimum. Original segment-index ties remain mandatory.
    var order = _wide_point_order(one.point, two.point, query)
    if order > 0 or (order == 0 and one_index >= two_index):
        return False
    if two.exact_witness:
        return True
    if len(two.cells) == 0:
        return False
    for cell in two.cells:
        if cell.low == cell.high:
            continue
        var scale = max(one.scale, cell.scale)
        var upper = _rebase_upper(one.upper, one.scale, scale)
        var lower = _rebase_lower(cell.lower, cell.scale, scale)
        if one_index < two_index:
            if upper > lower:
                return False
        elif upper >= lower:
            return False
    return True


def _plan_box_classification(
    width: _Interval, difference: _Interval
) -> Optional[Bool]:
    if not width.is_finite():
        return None
    if width.high <= 0.0:
        return False
    if width.low > 0.0 and difference.high < 0.0:
        return True
    if difference.low >= 0.0:
        return False
    return None


def _minimizer_plan_width_upper(
    width: _Interval, upper: Float64, scale: Float64
) -> Float64:
    # Restricted to exact minimizing points: plan_square <= space_square
    # <= upper*scale^2. This does NOT bound H at every point of the cell.
    # The width box still covers every stored width on that cell.
    var diameter = width / _Interval.point(scale)
    return (
        _Interval.point(4.0) * _Interval.point(upper) - diameter.square()
    ).high


def _lane_certificate_contains(
    road: Road,
    section: Int,
    lane: Int,
    location: Vector3,
    mut certificate: _LaneCertificate,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
) raises -> Bool:
    _require_sum2_environment()
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    if certificate.exact_witness:
        # The returned s is itself a proved minimizer. Use the exact stored
        # point predicate, including strict exclusion of a boundary point.
        if (
            info_index(
                road.sections[section].lanes[lane].info.widths, certificate.s
            )
            < 0
        ):
            raise Error("A lane classification needs a width record")
        return _wide_plan_contains(
            certificate.point,
            query,
            road.lane_width(section, lane, certificate.s),
        )
    if len(certificate.cells) == 0:
        raise Error("Lane classification needs possible minimizing cells")
    if (
        info_index(
            road.sections[section].lanes[lane].info.widths, certificate.s
        )
        < 0
    ):
        raise Error("A lane classification needs a width record")
    # The approximate returned waypoint must agree with every possible
    # minimizing cell. Cell consensus alone does not classify this sample.
    var result = _wide_plan_contains(
        certificate.point, query, road.lane_width(section, lane, certificate.s)
    )
    if len(certificate.cells) > max_nodes - certificate.nodes:
        raise Error("Lane classification exhausted its interval work limit")
    var pending = certificate.cells.copy()
    while len(pending) > 0:
        var cell = pending.pop()
        if certificate.nodes >= max_nodes:
            raise Error("Lane classification exhausted its interval work limit")
        certificate.nodes += 1
        # Width comes first. A near-zero distance certificate can classify
        # its minimizing set without resolving a broad curve/quadrature cell.
        var width = _lane_width_box(road, section, lane, cell.low, cell.high)
        if not width.is_finite():
            raise Error("Lane classification needs a finite width enclosure")
        var minimum_upper = _minimizer_plan_width_upper(
            width, certificate.upper, certificate.scale
        )
        var resolved: Optional[Bool]
        if width.high <= 0.0:
            resolved = False
        elif width.low > 0.0 and minimum_upper < 0.0:
            resolved = True
        elif cell.low == cell.high:
            var point = _checked_center(
                road, section, lane, cell.low, certificate.terms, max_terms
            )
            resolved = _wide_plan_contains(
                point, query, road.lane_width(section, lane, cell.low)
            )
        else:
            var work = _reference_work(road, cell.low, cell.high)
            if work < 0:
                raise Error(
                    "Lane classification cannot resolve a minimizing cell"
                )
            if certificate.terms > max_terms - work:
                raise Error(
                    "Lane classification exhausted its quadrature work limit"
                )
            certificate.terms += work
            var point = _lane_jet(road, section, lane, cell.low, cell.high)
            # A strict 3D lower bound can remove this entire cell from the
            # minimizing set before its planar classification is resolved.
            if (
                _scaled_point_distance_box(
                    point, location, certificate.scale
                ).low
                > certificate.upper
            ):
                continue
            var full_difference = _scaled_plan_width_box(
                point, width, location, certificate.scale
            )
            var restricted_high = min(full_difference.high, minimum_upper)
            if full_difference.low > restricted_high:
                # These bounds prove this cell has no exact minimizing point.
                # It cannot constrain classification of the minimizing set.
                continue
            var minimizing_difference = _Interval(
                full_difference.low, restricted_high
            )
            resolved = _plan_box_classification(width, minimizing_difference)
        if not Bool(resolved):
            var middle = _midpoint(cell.low, cell.high)
            if middle <= cell.low or middle >= cell.high or cell.depth >= 96:
                raise Error(
                    "Lane classification is unresolved over a possible"
                    " minimizing cell"
                )
            # A loose minimum certificate need not be a loose classification
            # result. Both closed halves cover the original cell; subdivision
            # uses the SAME cumulative node/term ledger and retained depth.
            pending.append(
                _ClosedInterval(
                    middle, cell.high, cell.depth + 1, cell.lower, cell.scale
                )
            )
            pending.append(
                _ClosedInterval(
                    cell.low, middle, cell.depth + 1, cell.lower, cell.scale
                )
            )
            continue
        if result != resolved.value():
            raise Error(
                "Lane classification disagrees across possible minimizing cells"
            )
    return result


def _refine_lane(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    seed: Float64,
    seed_distance: Float64,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
) raises -> Tuple[Float64, Float64]:
    # Keep the private compatibility return. Map consumes the certificate.
    var result = _refine_lane_certificate(
        road,
        section,
        lane,
        low,
        high,
        location,
        seed,
        seed_distance,
        max_nodes,
        max_terms,
        max_depth,
    )
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    return (result.s, _legacy_square(result.point, query))


def _refine_lane_certificate(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    seed: Float64,
    seed_distance: Float64,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
    spiral_proof: Optional[_SpiralDomainProof] = None,
    seed_only: Bool = False,
) raises -> _LaneCertificate:
    _require_sum2_environment()
    if not (isfinite(low) and isfinite(high) and isfinite(seed)):
        raise Error("Lane refinement needs finite parameter bounds")
    if high < low or seed < low or seed > high:
        raise Error("Lane refinement seed is outside its parameter interval")
    var nodes = 0
    var terms = 0
    if low >= 0.0:
        var axis = _axis_lane_minimum(
            road,
            section,
            lane,
            low,
            high,
            location,
            max_nodes,
            max_terms,
            max_depth,
        )
        # The optional rounded proof cannot admit a parameter box that
        # is non-singleton and touches zero, or leaves its guarded range.
        # Check that necessary
        # condition before reserving a profile traversal that must decline.
        # The original axis path above has already validated the lane.
        if not axis and _RoundedBox.bounds(low, high).known:
            axis = _rounded_axis_lane_minimum(
                road,
                section,
                lane,
                low,
                high,
                location,
                nodes,
                terms,
                max_nodes,
                max_terms,
                max_depth,
            )
        if Bool(axis):
            ref exact = axis.value()
            var query: Array[Float64, 3] = [
                Float64(location.x),
                Float64(location.y),
                Float64(location.z),
            ]
            return _exact_lane_certificate(
                exact[0], exact[2], query, exact[3], exact[4]
            )
    var best = seed
    if max_nodes <= 0:
        raise Error("Lane refinement exhausted its interval work limit")
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    _finite_point(query)
    if seed_only:
        # Staged admission can exclude this seed without a search node.
        # Reserve its scalar/profile work now, before the evaluator call.
        if nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        nodes += 1
    var best_point = _checked_center(
        road, section, lane, best, terms, max_terms
    )
    if low == high:
        # Seed-only admission already reserved this sole scalar leaf.
        if not seed_only:
            if nodes >= max_nodes:
                raise Error("Lane refinement exhausted its interval work limit")
            nodes += 1
        return _exact_lane_certificate(best, best_point, query, nodes, terms)
    var scale = _point_gap_scale(best_point, query)
    if scale == 0.0:
        scale = 1.0
    var score = _normalized_square[3](best_point, query, scale)
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(low, high, 0, 0.0, scale)
    ]
    var certificate = _LaneCertificate(
        best,
        best_point.copy(),
        scale,
        0.0,
        score.high,
        False,
        cells^,
        nodes,
        terms,
    )
    if seed_only:
        # The full zero-lower cell remains unresolved. Its scalar witness and
        # all seed/fast-path work survive into ordinary or goal resumption.
        return certificate^
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    _run_lane_search(
        road,
        section,
        lane,
        low,
        high,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        max_nodes,
        max_terms,
        max_depth,
        spiral_proof,
    )
    return certificate^


def _search_accuracy(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    best: Float64,
    best_lower: Float64,
    scale: Float64,
    requested_gap: Optional[Tuple[Float64, Float64]],
) raises -> Float64:
    var allowance = _scaled_accuracy(
        road, section, lane, low, high, best, best_lower, scale
    )
    if Bool(requested_gap):
        var request = requested_gap.value()
        # The request is a squared-distance gap in its saved scale units.
        # Downward rebasing and min can only tighten the original allowance.
        allowance = min(allowance, _rebase_lower(request[0], request[1], scale))
    return allowance


def _next_resume_gap(
    certificate: _LaneCertificate,
    previous_gap: Float64,
    previous_scale: Float64,
) -> Float64:
    # Scheduling only. Every accepted cell still needs the original proof.
    var gap = max(
        0.0,
        (
            _Interval.point(certificate.upper)
            - _Interval.point(certificate.lower)
        ).low,
    )
    if isfinite(previous_gap):
        gap = min(
            gap, _rebase_lower(previous_gap, previous_scale, certificate.scale)
        )
    return max(0.0, (_Interval.point(gap) * _Interval.point(0.25)).low)


def _reserve_rounded_arc_box(
    mut certificate: _LaneCertificate, max_nodes: Int, max_terms: Int
) raises:
    # Reserve before evaluating or allocating a private proof work item.
    # An ARC box has the same one reference term as _reference_work.
    if certificate.nodes >= max_nodes:
        raise Error("Lane refinement exhausted its interval work limit")
    certificate.nodes += 1
    if certificate.terms > max_terms - 1:
        raise Error("Lane refinement exhausted its quadrature work limit")
    certificate.terms += 1


def _try_rounded_arc_witness(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    query: Array[Float64, 3],
    mut certificate: _LaneCertificate,
    max_nodes: Int,
    max_terms: Int,
    max_depth: Int,
) raises -> Bool:
    # A transactional proof over the ORIGINAL domain. Equality can close
    # private proof cells, but cannot remove possible minimizing cells from
    # the old classification cover before this entire proof succeeds.
    # Only endpoint incumbents enter this initial proof. Interior minima
    # remain on the ordinary path without spending a speculative budget.
    if certificate.s != low and certificate.s != high:
        return False
    if len(road.info.geometries) != 1:
        return False
    if road.info.geometries[0].geometry.kind != ARC:
        return False
    _reserve_rounded_arc_box(certificate, max_nodes, max_terms)
    var context = _rounded_arc_context(road, section, lane, low, high)
    if not Bool(context):
        return False
    var model = context.value()
    # Preserve the existing strict-improvement parameter tie policy. This
    # attempt never substitutes another equal witness or searches a plateau.
    var witness = _checked_center(
        road, section, lane, certificate.s, certificate.terms, max_terms
    )
    for axis in range(3):
        if witness[axis] != certificate.point[axis]:
            return False
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    while len(pending) > 0:
        # This item was debited before insertion. Depth is measured from
        # the whole original domain, never from a retained subcell.
        var cell = pending.pop()
        var box = model.center(cell[0], cell[1])
        var corner: Array[Float64, 3] = [0.0, 0.0, 0.0]
        for axis in range(3):
            if not box[axis].known:
                return False
            corner[axis] = min(max(query[axis], box[axis].low), box[axis].high)
        if _wide_point_order(corner, witness, query) >= 0:
            continue
        var middle = _midpoint(cell[0], cell[1])
        if middle <= cell[0] or middle >= cell[1]:
            # Unknown is not an exact certificate. Ordinary search retains
            # the original cover and can compare the discrete endpoints.
            return False
        var sample = _checked_center(
            road, section, lane, middle, certificate.terms, max_terms
        )
        if _wide_point_order(sample, witness, query) < 0:
            return False
        if cell[2] >= max_depth:
            # This stronger optional proof reached its depth bound. Keep
            # the old solver's retained depths and failure decision intact.
            return False
        _reserve_rounded_arc_box(certificate, max_nodes, max_terms)
        _reserve_rounded_arc_box(certificate, max_nodes, max_terms)
        pending.append((middle, cell[1], cell[2] + 1))
        pending.append((cell[0], middle, cell[2] + 1))
    certificate = _exact_lane_certificate(
        certificate.s, witness, query, certificate.nodes, certificate.terms
    )
    return True


def _resume_lane_certificate(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    mut certificate: _LaneCertificate,
    requested_gap: Float64,
    request_scale: Float64,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
    spiral_proof: Optional[_SpiralDomainProof] = None,
) raises:
    # Keep the original requested-gap boundary. Ordinary completion and
    # external-witness goals use the distinct internal continuation entry.
    if not (isfinite(low) and isfinite(high)) or high < low:
        raise Error("Lane resumption needs finite ordered parameter bounds")
    if not isfinite(requested_gap) or requested_gap < 0.0:
        raise Error("Lane resumption needs a finite nonnegative gap")
    _continue_lane_certificate(
        road,
        section,
        lane,
        low,
        high,
        location,
        certificate,
        requested_gap,
        request_scale,
        max_nodes,
        max_terms,
        max_depth,
        spiral_proof,
    )


def _continue_lane_certificate(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    mut certificate: _LaneCertificate,
    requested_gap: Optional[Float64],
    request_scale: Float64,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
    spiral_proof: Optional[_SpiralDomainProof] = None,
    goal: Optional[_LaneExclusionGoal] = None,
) raises:
    _require_sum2_environment()
    # Internal precondition: same road snapshot, lane, query, and original
    # parameter domain as the certificate. Old strict exclusions stay valid.
    if not (isfinite(low) and isfinite(high)) or high < low:
        raise Error("Lane resumption needs finite ordered parameter bounds")
    if requested_gap:
        if not isfinite(requested_gap.value()) or requested_gap.value() < 0.0:
            raise Error("Lane resumption needs a finite nonnegative gap")
    if request_scale <= 0.0 or not _binary_power(request_scale):
        raise Error("Lane resumption needs a positive power-of-two scale")
    if goal:
        var target = goal.value()
        if not isfinite(target.upper) or target.upper < 0.0:
            raise Error("Lane exclusion needs a finite nonnegative upper bound")
        if target.scale <= 0.0 or not _binary_power(target.scale):
            raise Error("Lane exclusion needs a positive power-of-two scale")
    if (
        not isfinite(certificate.s)
        or certificate.s < low
        or certificate.s > high
    ):
        raise Error(
            "Lane resumption incumbent is outside its parameter interval"
        )
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    _finite_point(query)
    _finite_point(certificate.point)
    if certificate.nodes < 0 or certificate.terms < 0:
        raise Error("Lane resumption needs nonnegative consumed work")
    if certificate.exact_witness:
        return
    if len(certificate.cells) == 0:
        raise Error("Lane resumption needs possible minimizing cells")
    for cell in certificate.cells:
        if (
            not (isfinite(cell.low) and isfinite(cell.high))
            or cell.low < low
            or cell.high > high
            or cell.high < cell.low
        ):
            raise Error("Lane resumption cell is outside its original interval")
        if cell.depth < 0:
            raise Error("Lane resumption needs a nonnegative cell depth")
    if _try_rounded_arc_witness(
        road,
        section,
        lane,
        low,
        high,
        query,
        certificate,
        max_nodes,
        max_terms,
        max_depth,
    ):
        return
    var closed = _ClosedIntervals()
    var terminal = List[_ClosedInterval]()
    for cell in certificate.cells:
        if cell.low == cell.high:
            # These points were evaluated and ordered before export. Do not
            # discard their lower bounds/depths or charge an invented recheck.
            terminal.append(cell)
        else:
            closed.add(cell)
    var gap: Optional[Tuple[Float64, Float64]] = None
    if requested_gap:
        gap = (requested_gap.value(), request_scale)
    _run_lane_search(
        road,
        section,
        lane,
        low,
        high,
        location,
        certificate,
        List[Tuple[Float64, Float64, Int]](),
        closed^,
        terminal^,
        gap,
        max_nodes,
        max_terms,
        max_depth,
        spiral_proof,
        goal,
    )


def _run_lane_search(
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
) raises:
    # Fresh and resumed refinement share one solver. Counters and improved
    # incumbents are published immediately, including on an exception.
    # Until success, the older cell cover remains conservative and reusable.
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
                    if frozen:
                        center = _frozen_arc_expansion(
                            frozen.value(), center_s, location, scale
                        )
                    else:
                        center = _expansion_distance_jet(
                            road, section, lane, center_s, location, scale
                        )
                var delta = _Interval(lo, hi) - _Interval.point(center_s)
                var lower = max(natural, _global_lower(domain, center, delta))
                if lower > best_upper:
                    continue
                if (
                    _goal_excludes(lower, scale, goal)
                    or _next_up(best_upper - lower) <= tolerance
                ):
                    closed.add(_ClosedInterval(lo, hi, task[2], lower, scale))
                    continue
        if task[2] >= max_depth:
            raise Error(
                "Lane refinement exhausted its numerical accuracy limit"
            )
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


def _length_up(x: Float64, y: Float64, z: Float64) -> Float64:
    return (
        (
            _Interval.point(x).square()
            + _Interval.point(y).square()
            + _Interval.point(z).square()
        )
        .sqrt()
        .high
    )


def _whole_lane_box() -> Tuple[_Interval, _Interval, _Interval]:
    return (_Interval.whole(), _Interval.whole(), _Interval.whole())


def _finite_lane_box(box: Tuple[_Interval, _Interval, _Interval]) -> Bool:
    return box[0].is_finite() and box[1].is_finite() and box[2].is_finite()


struct _ProofNodeWork(ImplicitlyCopyable):
    # Global callers request hard refusal. Legacy local wrappers can retain
    # their original whole-box fallback when their unchanged local cap ends.
    var limit: Int
    var used: Int
    var fail_on_limit: Bool

    def __init__(out self, limit: Int = 16384, fail_on_limit: Bool = True):
        self.limit = limit
        self.used = 0
        self.fail_on_limit = fail_on_limit

    def take(mut self) raises -> Bool:
        if self.limit < 0 or self.used < 0 or self.used > self.limit:
            raise Error("Construction proof node budget is not valid")
        if self.used == self.limit:
            if self.fail_on_limit:
                raise Error(
                    "Map construction exhausted its global proof node budget"
                )
            return False
        # Charge before popping a cell or evaluating its unresolved count.
        self.used += 1
        return True


def _subdivided_lane_box(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    max_terms: Int,
    max_nodes: Int = 16384,
) raises -> Tuple[Tuple[_Interval, _Interval, _Interval], Int]:
    # Preserve the original local exhaustion result for existing callers.
    var nodes = _ProofNodeWork(max(0, max_nodes), fail_on_limit=False)
    return _subdivided_lane_box_with_nodes(
        road, section, lane, low, high, max_terms, nodes
    )


def _subdivided_lane_box_with_nodes(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    max_terms: Int,
    mut nodes: _ProofNodeWork,
) raises -> Tuple[Tuple[_Interval, _Interval, _Interval], Int]:
    var pending: List[Tuple[Float64, Float64]] = [(low, high)]
    var terms = 0
    var result = _whole_lane_box()
    var have_result = False
    while len(pending) > 0:
        if not nodes.take():
            return (_whole_lane_box(), terms)
        var task = pending.pop()
        var lo = task[0]
        var hi = task[1]
        var work = _reference_work(road, lo, hi)
        var box = _whole_lane_box()
        if work >= 0:
            if work > max_terms - terms:
                return (_whole_lane_box(), terms)
            terms += work
            # This traversal consumes only boxes. The value-only graph
            # retains the full Jet's exact value, error and branch bounds.
            var point = _lane_value_bound(road, section, lane, lo, hi)
            box = (
                point[0].rounded_value(),
                -point[1].rounded_value(),
                point[2].rounded_value(),
            )
        if not _finite_lane_box(box):
            var middle = _midpoint(lo, hi)
            if middle > lo and middle < hi:
                pending.append((middle, hi))
                pending.append((lo, middle))
                continue
            # No other Float64 parameter exists. Enclose both actual values,
            # but do not run an unresolved or unbudgeted quadrature count.
            var first_work = _reference_work(road, lo, lo)
            var last_work = _reference_work(road, hi, hi)
            if first_work < 0 or last_work < 0:
                return (_whole_lane_box(), terms)
            if first_work > max_terms - terms:
                return (_whole_lane_box(), terms)
            if last_work > max_terms - terms - first_work:
                return (_whole_lane_box(), terms)
            var first = _checked_center(
                road, section, lane, lo, terms, max_terms
            )
            var last = _checked_center(
                road, section, lane, hi, terms, max_terms
            )
            box = (
                _Interval(min(first[0], last[0]), max(first[0], last[0])),
                _Interval(min(first[1], last[1]), max(first[1], last[1])),
                _Interval(min(first[2], last[2]), max(first[2], last[2])),
            )
        if have_result:
            result = (
                result[0].hull(box[0]),
                result[1].hull(box[1]),
                result[2].hull(box[2]),
            )
        else:
            result = box
            have_result = True
    return (result, terms)


def _chord_error(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    max_terms: Int = 2000000,
) raises -> Float64:
    return _chord_certificate(
        road, section, lane, low, high, start, end, max_terms
    )[0]


def _chord_certificate(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    var captured = _SpiralRootCapture()
    return _chord_certificate_impl[False](
        road, section, lane, low, high, start, end, captured, max_terms
    )


def _chord_certificate_capture(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    captured = _SpiralRootCapture()
    return _chord_certificate_impl[True](
        road, section, lane, low, high, start, end, captured, max_terms
    )


def _chord_certificate_capture_with_nodes(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    mut nodes: _ProofNodeWork,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    captured = _SpiralRootCapture()
    return _chord_certificate_impl_with_nodes[True, False](
        road, section, lane, low, high, start, end, captured, nodes, max_terms
    )


def _chord_certificate_impl[
    capture: Bool
](
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    var nodes = _ProofNodeWork(fail_on_limit=False)
    return _chord_certificate_impl_with_nodes[capture, False](
        road, section, lane, low, high, start, end, captured, nodes, max_terms
    )


def _chord_certificate_capture_fast(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    var nodes = _ProofNodeWork(fail_on_limit=False)
    return _chord_certificate_capture_fast_with_nodes(
        road, section, lane, low, high, start, end, captured, nodes, max_terms
    )


def _chord_certificate_capture_fast_with_nodes(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    mut nodes: _ProofNodeWork,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    captured = _SpiralRootCapture()
    return _chord_certificate_impl_with_nodes[True, True](
        road, section, lane, low, high, start, end, captured, nodes, max_terms
    )


def _chord_certificate_impl_with_nodes[
    capture: Bool, use_envelope: Bool
](
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    start: Vector3,
    end: Vector3,
    mut captured: _SpiralRootCapture,
    mut nodes: _ProofNodeWork,
    max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    var work = _reference_work(road, low, high)
    var point = _unknown_point()
    var spent = 0
    if work >= 0 and work <= max_terms:
        spent = work
        comptime if capture:
            comptime if use_envelope:
                var fast = _try_lane_envelope_capture(
                    road, section, lane, low, high, captured, spent, max_terms
                )
                if fast:
                    point = fast.value()
                else:
                    point = _lane_jet_capture(
                        road, section, lane, low, high, captured
                    )
            else:
                point = _lane_jet_capture(
                    road, section, lane, low, high, captured
                )
        else:
            point = _lane_jet(road, section, lane, low, high)
    var box = (
        point[0].rounded_value(),
        -point[1].rounded_value(),
        point[2].rounded_value(),
    )
    if not _finite_lane_box(box):
        var enclosure = _subdivided_lane_box_with_nodes(
            road, section, lane, low, high, max_terms - spent, nodes
        )
        box = enclosure[0]
        spent += enclosure[1]
    # Any point in the curve box and any point of the chord give a valid,
    # possibly loose, deviation bound. This remains valid at branch jumps.
    var x = box[0] - _Interval(
        min(Float64(start.x), Float64(end.x)),
        max(Float64(start.x), Float64(end.x)),
    )
    var y = box[1] - _Interval(
        min(Float64(start.y), Float64(end.y)),
        max(Float64(start.y), Float64(end.y)),
    )
    var z = box[2] - _Interval(
        min(Float64(start.z), Float64(end.z)),
        max(Float64(start.z), Float64(end.z)),
    )
    var natural = _length_up(x.magnitude(), y.magnitude(), z.magnitude())
    var derivative = _length_up(
        point[0].second.magnitude(),
        point[1].second.magnitude(),
        point[2].second.magnitude(),
    )
    if not isfinite(derivative):
        return (natural, box, spent)
    var first_work = _reference_work(road, low, low)
    var last_work = _reference_work(road, high, high)
    if first_work < 0 or last_work < 0:
        return (natural, box, spent)
    if first_work > max_terms - spent:
        return (natural, box, spent)
    if last_work > max_terms - spent - first_work:
        return (natural, box, spent)
    var first = _checked_center(road, section, lane, low, spent, max_terms)
    var last = _checked_center(road, section, lane, high, spent, max_terms)
    var conversion = _length_up(
        max(
            (
                _Interval.point(first[0]) - _Interval.point(Float64(start.x))
            ).magnitude(),
            (
                _Interval.point(last[0]) - _Interval.point(Float64(end.x))
            ).magnitude(),
        ),
        max(
            (
                _Interval.point(first[1]) - _Interval.point(Float64(start.y))
            ).magnitude(),
            (
                _Interval.point(last[1]) - _Interval.point(Float64(end.y))
            ).magnitude(),
        ),
        max(
            (
                _Interval.point(first[2]) - _Interval.point(Float64(start.z))
            ).magnitude(),
            (
                _Interval.point(last[2]) - _Interval.point(Float64(end.z))
            ).magnitude(),
        ),
    )
    var evaluation = _length_up(point[0].error, point[1].error, point[2].error)
    var span = _Interval.point(high) - _Interval.point(low)
    # For each scalar twice differentiable function, the linear-interpolant
    # error is at most h^2*sup|f''|/8. Roundoff at the curve and both endpoint
    # evaluations adds at most twice the uniform evaluator error.
    var smooth = (
        span.square() * _Interval.point(0.125) * _Interval.point(derivative)
        + _Interval.point(2.0) * _Interval.point(evaluation)
        + _Interval.point(conversion)
    ).high
    return (min(natural, smooth), box, spent)


def _admission_roundoff(scale: Float64, deviation: Float64) -> Float64:
    # RTree uses Float64 arithmetic on finite Float32 endpoints and query.
    # A clamped scalar projection t lies in [0,1] regardless of its condition.
    # Endpoint subtraction, multiplication and residual subtraction give
    # <11u*M error per axis. Squared norm and sqrt contribute <28u*M more;
    # the Euclidean total is <48u*M. Box bounds are <16u*M. Two 64u bounds
    # cover the index distance and the best center distance. No transcendental
    # assumption or sampled chord tolerance enters this allowance.
    return (
        _Interval.point(1.4210854715202004e-14)
        * (_Interval.point(scale) + _Interval.point(deviation))
    ).high


def _lane_box_can_improve(
    box: Tuple[_Interval, _Interval, _Interval],
    location: Vector3,
    best_point: Array[Float64, 3],
) raises -> Bool:
    # Query only the cached full-evaluator enclosure. Unknown boxes retain
    # the candidate; they never become a false empty or off-road result.
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var scale = _point_gap_scale(best_point, query)
    if scale == 0.0:
        scale = 1.0
    var upper = _normalized_square[3](best_point, query, scale).high
    var divisor = _Interval.point(scale)
    var x = (box[0] - _Interval.point(query[0])) / divisor
    var y = (box[1] - _Interval.point(query[1])) / divisor
    var z = (box[2] - _Interval.point(query[2])) / divisor
    var lower = max(0.0, (x.square() + y.square() + z.square()).low)
    return lower <= upper


def _indexed_curve_lower(key: Float64, deviation: Float64) -> Float64:
    # Requires #589's finite stored-Float32 key contract: K <= (1+2^-40)D.
    # Divide and take the square root outward, then subtract the certified
    # full-curve distance to the stored chord. Unknown input disables pruning.
    if (
        not isfinite(key)
        or key < 0.0
        or not isfinite(deviation)
        or deviation < 0.0
    ):
        return 0.0
    var squared = _Interval.point(key) / _Interval.point(
        1.0000000000009094947017729282379150390625
    )
    var radius = _Interval(max(0.0, squared.low), max(0.0, squared.high)).sqrt()
    return max(0.0, (radius - _Interval.point(deviation)).low)
