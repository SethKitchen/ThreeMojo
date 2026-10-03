# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite global refinement and admission certificates for lane curves.

The numerical expressions live in curve_bounds. This module owns finite
local work and accuracy limits. An unresolved interval raises an Error. It
never reports an off-road result or a partially searched minimum.
"""

from extensions.carla.curve_bounds import (
    _lane_jet, _lane_width_box, _scaled_plan_width_box, _reference_work, _scaled_point_distance_box, _scaled_point_distance_jet, _unknown_point, _expansion_distance_jet,
)
from extensions.carla.curve_distance import (
    _finite_point, _normalized_square, _point_gap_scale, _wide_point_order, _wide_plan_contains,
)
from extensions.carla.curve_interval import _Interval, _Jet, _binary_power, _next_down, _next_up
from extensions.carla.geometry import LINE
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
from std.math import inf, isfinite, sqrt
from std.memory import bitcast


def _legacy_square(point: Array[Float64, 3], query: Array[Float64, 3]) -> Float64:
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
    road: Road, section: Int, lane: Int, s: Float64,
    mut terms: Int, max_terms: Int,
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
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3,
    max_nodes: Int = 16384, max_terms: Int = 2000000, max_depth: Int = 96,
) raises -> Optional[Tuple[Float64, Float64, Array[Float64, 3], Int, Int]]:
    # A zero-heading LINE with constant lateral and vertical coordinates has
    # a monotone stored x evaluator, including subtraction, clamp, and rounding.
    # This is an exact stored-point minimum, not an affine projection heuristic.
    # Return s, the legacy square, the exact minimum witness, nodes, and terms.
    # Plateau s selection follows this deterministic search: endpoint, inverse
    # hit, then bit midpoint; a final equal bracket keeps its lower s. It does
    # not promise the first s on a plateau or alter segment-index tie ordering.
    if not (isfinite(low) and isfinite(high)) or low < 0.0 or high < low:
        raise Error("Axis lane search needs finite nonnegative parameter bounds")
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
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
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
            raise Error("Lane refinement exhausted its numerical accuracy limit")
        nodes += 1
        depth += 1
        var middle_bits = lo_bits + (hi_bits - lo_bits) // UInt64(2)
        var middle = bitcast[DType.float64](middle_bits)
        var point = _checked_center(road, section, lane, middle, terms, max_terms)
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


def _local_seed(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    query: Array[Float64, 3], best: Float64, best_point: Array[Float64, 3],
    mut terms: Int, max_terms: Int,
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
    if center <= low or center >= high:
        return _midpoint(low, high)
    return center


def _global_lower(
    domain: _Jet, center: _Jet, delta: _Interval
) -> Float64:
    var natural = domain.rounded_value().low
    if not domain.second.is_finite() or not center.first.is_finite():
        return max(0.0, natural)
    # Taylor's theorem for the actual stored polynomial/rational expression.
    # The separately propagated scalar evaluation error remains in the bound.
    var taylor = center.value + center.first * delta + (
        _Interval.point(0.5) * domain.second * delta.square()
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
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    best: Float64, best_lower: Float64, scale: Float64,
) raises -> Float64:
    # The spatial target is unchanged. Division precedes the square.
    var spatial_scale = high - low
    var width = abs(road.lane_width(section, lane, best))
    if width > 0.0:
        spatial_scale = min(spatial_scale, width)
    var spatial = (_Interval.point(spatial_scale) / _Interval.point(scale)
                   * _Interval.point(0.00000095367431640625))
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


def _rebase_lower(lower: Float64, old_scale: Float64, scale: Float64) -> Float64:
    if old_scale == scale:
        return lower
    var ratio = _Interval.point(old_scale) / _Interval.point(scale)
    return max(0.0, (_Interval.point(lower) * ratio.square()).low)


def _certificate_within_gap(
    lower: Float64, old_scale: Float64, scale: Float64,
    upper: Float64, tolerance: Float64,
) -> Bool:
    return _next_up(upper - _rebase_lower(lower, old_scale, scale)) <= tolerance



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
        mut self, scale: Float64, upper: Float64, tolerance: Float64
    ) -> Optional[Tuple[Float64, Float64, Int]]:
        # The caller first checks needs_validation. Swap-pop removes only
        # this unvalidated item, so the validated prefix remains intact.
        var certificate = self.values[self.validated]
        if _certificate_within_gap(certificate.lower, certificate.scale, scale, upper, tolerance):
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
    s: Float64, point: Array[Float64, 3], query: Array[Float64, 3],
    nodes: Int, terms: Int,
) raises -> _LaneCertificate:
    var scale = _point_gap_scale(point, query)
    if scale == 0.0:
        scale = 1.0
    var score = _normalized_square[3](point, query, scale)
    var cells: List[_ClosedInterval] = [_ClosedInterval(s, s, 0, score.low, scale)]
    return _LaneCertificate(s, point.copy(), scale, score.low, score.high, True, cells^, nodes, terms)


def _finish_lane_certificate(
    best: Float64, point: Array[Float64, 3], query: Array[Float64, 3],
    closed: _ClosedIntervals, terminal: List[_ClosedInterval],
    nodes: Int, terms: Int,
) raises -> _LaneCertificate:
    var scale = _point_gap_scale(point, query)
    if scale == 0.0:
        return _exact_lane_certificate(best, point, query, nodes, terms)
    var score = _normalized_square[3](point, query, scale)
    var lower = score.high
    var all_terminal = True
    var cells = List[_ClosedInterval]()
    # Hard exclusions stay excluded after an incumbent improvement. Keep
    # every other possible minimizer, including evaluated adjacent Floats.
    for cell in closed.values:
        var bound = _rebase_lower(cell.lower, cell.scale, scale)
        if bound <= score.high:
            lower = min(lower, bound)
            all_terminal = all_terminal and cell.low == cell.high
            cells.append(cell)
    for cell in terminal:
        var bound = _rebase_lower(cell.lower, cell.scale, scale)
        if bound <= score.high:
            lower = min(lower, bound)
            all_terminal = all_terminal and cell.low == cell.high
            cells.append(cell)
    if len(cells) == 0:
        raise Error("Lane certificate lost its possible minimizing cells")
    # Each terminal point was already compared with this incumbent by the
    # shared search. Only complete discrete coverage establishes exactness.
    return _LaneCertificate(best, point.copy(), scale, lower, score.high, all_terminal, cells^, nodes, terms)


def _rebase_upper(upper: Float64, old_scale: Float64, scale: Float64) -> Float64:
    if old_scale == scale:
        return upper
    var ratio = _Interval.point(old_scale) / _Interval.point(scale)
    return max(0.0, (_Interval.point(upper) * ratio.square()).high)


def _lane_certificate_dominates(
    one: _LaneCertificate, one_index: Int,
    two: _LaneCertificate, two_index: Int,
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


def _plan_box_classification(width: _Interval, difference: _Interval) -> Optional[Bool]:
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
    return (_Interval.point(4.0) * _Interval.point(upper) - diameter.square()).high


def _lane_certificate_contains(
    road: Road, section: Int, lane: Int, location: Vector3,
    mut certificate: _LaneCertificate,
    max_nodes: Int = 16384, max_terms: Int = 2000000,
) raises -> Bool:
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
    if certificate.exact_witness:
        # The returned s is itself a proved minimizer. Use the exact stored
        # point predicate, including strict exclusion of a boundary point.
        if info_index(road.sections[section].lanes[lane].info.widths, certificate.s) < 0:
            raise Error("A lane classification needs a width record")
        return _wide_plan_contains(certificate.point, query, road.lane_width(section, lane, certificate.s))
    if len(certificate.cells) == 0:
        raise Error("Lane classification needs possible minimizing cells")
    if info_index(road.sections[section].lanes[lane].info.widths, certificate.s) < 0:
        raise Error("A lane classification needs a width record")
    # The approximate returned waypoint must agree with every possible
    # minimizing cell. Cell consensus alone does not classify this sample.
    var result = _wide_plan_contains(certificate.point, query, road.lane_width(section, lane, certificate.s))
    for cell in certificate.cells:
        if certificate.nodes >= max_nodes:
            raise Error("Lane classification exhausted its interval work limit")
        certificate.nodes += 1
        # Width comes first. A near-zero distance certificate can classify
        # its minimizing set without resolving a broad curve/quadrature cell.
        var width = _lane_width_box(road, section, lane, cell.low, cell.high)
        if not width.is_finite():
            raise Error("Lane classification needs a finite width enclosure")
        var minimum_upper = _minimizer_plan_width_upper(width, certificate.upper, certificate.scale)
        var resolved: Optional[Bool]
        if width.high <= 0.0:
            resolved = False
        elif width.low > 0.0 and minimum_upper < 0.0:
            resolved = True
        elif cell.low == cell.high:
            var point = _checked_center(road, section, lane, cell.low, certificate.terms, max_terms)
            resolved = _wide_plan_contains(point, query, road.lane_width(section, lane, cell.low))
        else:
            var work = _reference_work(road, cell.low, cell.high)
            if work < 0:
                raise Error("Lane classification cannot resolve a minimizing cell")
            if certificate.terms > max_terms - work:
                raise Error("Lane classification exhausted its quadrature work limit")
            certificate.terms += work
            var point = _lane_jet(road, section, lane, cell.low, cell.high)
            var full_difference = _scaled_plan_width_box(point, width, location, certificate.scale)
            var restricted_high = min(full_difference.high, minimum_upper)
            if full_difference.low > restricted_high:
                # These bounds prove this cell has no exact minimizing point.
                # It cannot constrain classification of the minimizing set.
                continue
            var minimizing_difference = _Interval(full_difference.low, restricted_high)
            resolved = _plan_box_classification(width, minimizing_difference)
        if not Bool(resolved):
            raise Error("Lane classification is unresolved over a possible minimizing cell")
        if result != resolved.value():
            raise Error("Lane classification disagrees across possible minimizing cells")
    return result


def _refine_lane(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, seed: Float64, seed_distance: Float64,
    max_nodes: Int = 16384, max_terms: Int = 2000000, max_depth: Int = 96,
) raises -> Tuple[Float64, Float64]:
    # Keep the private compatibility return. Map consumes the certificate.
    var result = _refine_lane_certificate(
        road, section, lane, low, high, location, seed, seed_distance,
        max_nodes, max_terms, max_depth,
    )
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
    return (result.s, _legacy_square(result.point, query))


def _refine_lane_certificate(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, seed: Float64, seed_distance: Float64,
    max_nodes: Int = 16384, max_terms: Int = 2000000, max_depth: Int = 96,
) raises -> _LaneCertificate:
    if not (isfinite(low) and isfinite(high) and isfinite(seed)):
        raise Error("Lane refinement needs finite parameter bounds")
    if high < low or seed < low or seed > high:
        raise Error("Lane refinement seed is outside its parameter interval")
    if low >= 0.0:
        var axis = _axis_lane_minimum(
            road, section, lane, low, high, location,
            max_nodes, max_terms, max_depth,
        )
        if Bool(axis):
            ref exact = axis.value()
            var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
            return _exact_lane_certificate(exact[0], exact[2], query, exact[3], exact[4])
    var best = seed
    var nodes = 0
    var terms = 0
    if max_nodes <= 0:
        raise Error("Lane refinement exhausted its interval work limit")
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
    _finite_point(query)
    var best_point = _checked_center(road, section, lane, best, terms, max_terms)
    if low == high:
        return _exact_lane_certificate(best, best_point, query, 1, terms)
    var scale = _point_gap_scale(best_point, query)
    if scale == 0.0:
        scale = 1.0
    var score = _normalized_square[3](best_point, query, scale)
    var cells: List[_ClosedInterval] = [_ClosedInterval(low, high, 0, 0.0, scale)]
    var certificate = _LaneCertificate(best, best_point.copy(), scale, 0.0, score.high, False, cells^, nodes, terms)
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    _run_lane_search(
        road, section, lane, low, high, location, certificate,
        pending^, _ClosedIntervals(), List[_ClosedInterval](), None,
        max_nodes, max_terms, max_depth,
    )
    return certificate^


def _search_accuracy(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    best: Float64, best_lower: Float64, scale: Float64,
    requested_gap: Optional[Tuple[Float64, Float64]],
) raises -> Float64:
    var allowance = _scaled_accuracy(road, section, lane, low, high, best, best_lower, scale)
    if Bool(requested_gap):
        var request = requested_gap.value()
        # The request is a squared-distance gap in its saved scale units.
        # Downward rebasing and min can only tighten the original allowance.
        allowance = min(allowance, _rebase_lower(request[0], request[1], scale))
    return allowance


def _next_resume_gap(
    certificate: _LaneCertificate, previous_gap: Float64,
    previous_scale: Float64,
) -> Float64:
    # Scheduling only. Every accepted cell still needs the original proof.
    var gap = max(0.0, (_Interval.point(certificate.upper) - _Interval.point(certificate.lower)).low)
    if isfinite(previous_gap):
        gap = min(gap, _rebase_lower(previous_gap, previous_scale, certificate.scale))
    return max(0.0, (_Interval.point(gap) * _Interval.point(0.25)).low)


def _resume_lane_certificate(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, mut certificate: _LaneCertificate,
    requested_gap: Float64, request_scale: Float64,
    max_nodes: Int = 16384, max_terms: Int = 2000000, max_depth: Int = 96,
) raises:
    # Internal precondition: same road snapshot, lane, query, and original
    # parameter domain as the certificate. Old strict exclusions stay valid.
    if not (isfinite(low) and isfinite(high)) or high < low:
        raise Error("Lane resumption needs finite ordered parameter bounds")
    if not isfinite(requested_gap) or requested_gap < 0.0:
        raise Error("Lane resumption needs a finite nonnegative gap")
    if request_scale <= 0.0 or not _binary_power(request_scale):
        raise Error("Lane resumption needs a positive power-of-two scale")
    if not isfinite(certificate.s) or certificate.s < low or certificate.s > high:
        raise Error("Lane resumption incumbent is outside its parameter interval")
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
    _finite_point(query)
    _finite_point(certificate.point)
    if certificate.nodes < 0 or certificate.terms < 0:
        raise Error("Lane resumption needs nonnegative consumed work")
    if certificate.exact_witness:
        return
    var closed = _ClosedIntervals()
    var terminal = List[_ClosedInterval]()
    for cell in certificate.cells:
        if not (isfinite(cell.low) and isfinite(cell.high)) or cell.low < low or cell.high > high or cell.high < cell.low:
            raise Error("Lane resumption cell is outside its original interval")
        if cell.depth < 0:
            raise Error("Lane resumption needs a nonnegative cell depth")
        if cell.low == cell.high:
            # These points were evaluated and ordered before export. Do not
            # discard their lower bounds/depths or charge an invented recheck.
            terminal.append(cell)
        else:
            closed.add(cell)
    if len(closed.values) == 0 and len(terminal) == 0:
        raise Error("Lane resumption needs possible minimizing cells")
    _run_lane_search(
        road, section, lane, low, high, location, certificate,
        List[Tuple[Float64, Float64, Int]](), closed^, terminal^,
        (requested_gap, request_scale), max_nodes, max_terms, max_depth,
    )


def _run_lane_search(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, mut certificate: _LaneCertificate,
    var pending: List[Tuple[Float64, Float64, Int]],
    var closed: _ClosedIntervals, var terminal: List[_ClosedInterval],
    requested_gap: Optional[Tuple[Float64, Float64]],
    max_nodes: Int, max_terms: Int, max_depth: Int,
) raises:
    # Fresh and resumed refinement share one solver. Counters and improved
    # incumbents are published immediately, including on an exception.
    # Until success, the older cell cover remains conservative and reusable.
    var best = certificate.s
    var best_point = certificate.point.copy()
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
    while len(pending) > 0 or closed.needs_validation():
        if certificate.nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        certificate.nodes += 1
        if len(pending) == 0:
            # A later winner can reduce width or cross a distance ULP binade.
            # Recheck every tolerance-closed region against the final budget.
            var scale = _point_gap_scale(best_point, query)
            if scale == 0.0:
                certificate = _exact_lane_certificate(best, best_point, query, certificate.nodes, certificate.terms)
                return
            var score = _normalized_square[3](best_point, query, scale)
            var tolerance = _search_accuracy(road, section, lane, low, high, best, score.low, scale, requested_gap)
            var reopened = closed.recheck(scale, score.high, tolerance)
            if Bool(reopened):
                pending.append(reopened.value())
            continue
        var task = pending.pop()
        var lo = task[0]
        var hi = task[1]
        var middle = _midpoint(lo, hi)
        var sample = middle
        var edge = 0
        while edge < 3:
            if edge == 1:
                sample = lo
            elif edge == 2:
                sample = hi
            var point = _checked_center(road, section, lane, sample, certificate.terms, max_terms)
            if middle <= lo or middle >= hi:
                var point_scale = _point_gap_scale(point, query)
                if point_scale == 0.0:
                    point_scale = 1.0
                var point_lower = _normalized_square[3](point, query, point_scale).low
                terminal.append(_ClosedInterval(sample, sample, task[2], point_lower, point_scale))
            if _wide_point_order(point, best_point, query) < 0:
                best = sample
                best_point = point^
                certificate.s = best
                certificate.point = best_point.copy()
                closed.reset()
            edge += 1
        var scale = _point_gap_scale(best_point, query)
        if scale == 0.0:
            # Componentwise coincidence establishes the exact global minimum.
            certificate = _exact_lane_certificate(best, best_point, query, certificate.nodes, certificate.terms)
            return
        if middle <= lo or middle >= hi:
            continue
        var best_bounds = _normalized_square[3](best_point, query, scale)
        var best_upper = best_bounds.high
        var work = _reference_work(road, lo, hi)
        if work >= 0:
            if certificate.terms > max_terms - work:
                raise Error("Lane refinement exhausted its quadrature work limit")
            certificate.terms += work
            var point_domain = _lane_jet(road, section, lane, lo, hi)
            var natural = _scaled_point_distance_box(point_domain, location, scale).low
            if natural > best_upper:
                continue
            var domain = _scaled_point_distance_jet(point_domain, location, scale)
            if domain.second.low > 0.0 and isfinite(hi - lo):
                var local = _local_seed(
                    road, section, lane, lo, hi, query, best, best_point,
                    certificate.terms, max_terms,
                )
                if local[0] != best:
                    closed.reset()
                best = local[0]
                best_point = local[1].copy()
                certificate.s = best
                certificate.point = best_point.copy()
                scale = _point_gap_scale(best_point, query)
                if scale == 0.0:
                    certificate = _exact_lane_certificate(best, best_point, query, certificate.nodes, certificate.terms)
                    return
                best_bounds = _normalized_square[3](best_point, query, scale)
                best_upper = best_bounds.high
                # Scale changes invalidate all normalized distance bounds.
                natural = _scaled_point_distance_box(point_domain, location, scale).low
                if natural > best_upper:
                    continue
                domain = _scaled_point_distance_jet(point_domain, location, scale)
            # A clamped singleton endpoint can have a different jet from
            # the interior branch. Taylor bounds need that same branch.
            var center_s = _expansion_center(lo, hi, best)
            var center_work = _reference_work(road, center_s, center_s)
            if center_work >= 0:
                if certificate.terms > max_terms - center_work:
                    raise Error("Lane refinement exhausted its quadrature work limit")
                certificate.terms += center_work
                var center = _expansion_distance_jet(
                    road, section, lane, center_s, location, scale
                )
                var delta = _Interval(lo, hi) - _Interval.point(center_s)
                var lower = max(natural, _global_lower(domain, center, delta))
                if lower > best_upper:
                    continue
                var tolerance = _search_accuracy(
                    road, section, lane, low, high, best, best_bounds.low, scale, requested_gap
                )
                if _next_up(best_upper - lower) <= tolerance:
                    closed.add(_ClosedInterval(lo, hi, task[2], lower, scale))
                    continue
        if task[2] >= max_depth:
            raise Error("Lane refinement exhausted its numerical accuracy limit")
        pending.append((middle, hi, task[2] + 1))
        pending.append((lo, middle, task[2] + 1))
    certificate = _finish_lane_certificate(
        best, best_point, query, closed, terminal, certificate.nodes, certificate.terms
    )


def _length_up(x: Float64, y: Float64, z: Float64) -> Float64:
    return (
        _Interval.point(x).square()
        + _Interval.point(y).square()
        + _Interval.point(z).square()
    ).sqrt().high



def _whole_lane_box() -> Tuple[_Interval, _Interval, _Interval]:
    return (_Interval.whole(), _Interval.whole(), _Interval.whole())


def _finite_lane_box(box: Tuple[_Interval, _Interval, _Interval]) -> Bool:
    return box[0].is_finite() and box[1].is_finite() and box[2].is_finite()


def _subdivided_lane_box(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    max_terms: Int, max_nodes: Int = 16384,
) raises -> Tuple[Tuple[_Interval, _Interval, _Interval], Int]:
    var pending: List[Tuple[Float64, Float64]] = [(low, high)]
    var nodes = 0
    var terms = 0
    var result = _whole_lane_box()
    var have_result = False
    while len(pending) > 0:
        if nodes >= max_nodes:
            return (_whole_lane_box(), terms)
        nodes += 1
        var task = pending.pop()
        var lo = task[0]
        var hi = task[1]
        var work = _reference_work(road, lo, hi)
        var box = _whole_lane_box()
        if work >= 0:
            if work > max_terms - terms:
                return (_whole_lane_box(), terms)
            terms += work
            var point = _lane_jet(road, section, lane, lo, hi)
            box = (point[0].rounded_value(), -point[1].rounded_value(), point[2].rounded_value())
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
            var first = _checked_center(road, section, lane, lo, terms, max_terms)
            var last = _checked_center(road, section, lane, hi, terms, max_terms)
            box = (
                _Interval(min(first[0], last[0]), max(first[0], last[0])),
                _Interval(min(first[1], last[1]), max(first[1], last[1])),
                _Interval(min(first[2], last[2]), max(first[2], last[2])),
            )
        if have_result:
            result = (result[0].hull(box[0]), result[1].hull(box[1]), result[2].hull(box[2]))
        else:
            result = box
            have_result = True
    return (result, terms)


def _chord_error(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    start: Vector3, end: Vector3, max_terms: Int = 2000000,
) raises -> Float64:
    return _chord_certificate(road, section, lane, low, high, start, end, max_terms)[0]


def _chord_certificate(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    start: Vector3, end: Vector3, max_terms: Int = 2000000,
) raises -> Tuple[Float64, Tuple[_Interval, _Interval, _Interval], Int]:
    var work = _reference_work(road, low, high)
    var point = _unknown_point()
    var spent = 0
    if work >= 0 and work <= max_terms:
        point = _lane_jet(road, section, lane, low, high)
        spent = work
    var box = (point[0].rounded_value(), -point[1].rounded_value(), point[2].rounded_value())
    if not _finite_lane_box(box):
        var enclosure = _subdivided_lane_box(road, section, lane, low, high, max_terms - spent)
        box = enclosure[0]
        spent += enclosure[1]
    # Any point in the curve box and any point of the chord give a valid,
    # possibly loose, deviation bound. This remains valid at branch jumps.
    var x = box[0] - _Interval(
        min(Float64(start.x), Float64(end.x)), max(Float64(start.x), Float64(end.x))
    )
    var y = box[1] - _Interval(
        min(Float64(start.y), Float64(end.y)), max(Float64(start.y), Float64(end.y))
    )
    var z = box[2] - _Interval(
        min(Float64(start.z), Float64(end.z)), max(Float64(start.z), Float64(end.z))
    )
    var natural = _length_up(x.magnitude(), y.magnitude(), z.magnitude())
    var derivative = _length_up(
        point[0].second.magnitude(), point[1].second.magnitude(), point[2].second.magnitude()
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
        max((_Interval.point(first[0]) - _Interval.point(Float64(start.x))).magnitude(),
            (_Interval.point(last[0]) - _Interval.point(Float64(end.x))).magnitude()),
        max((_Interval.point(first[1]) - _Interval.point(Float64(start.y))).magnitude(),
            (_Interval.point(last[1]) - _Interval.point(Float64(end.y))).magnitude()),
        max((_Interval.point(first[2]) - _Interval.point(Float64(start.z))).magnitude(),
            (_Interval.point(last[2]) - _Interval.point(Float64(end.z))).magnitude()),
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
    location: Vector3, best_point: Array[Float64, 3],
) raises -> Bool:
    # Query only the cached full-evaluator enclosure. Unknown boxes retain
    # the candidate; they never become a false empty or off-road result.
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), Float64(location.z)]
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
    if not isfinite(key) or key < 0.0 or not isfinite(deviation) or deviation < 0.0:
        return 0.0
    var squared = _Interval.point(key) / _Interval.point(1.0000000000009094947017729282379150390625)
    var radius = _Interval(max(0.0, squared.low), max(0.0, squared.high)).sqrt()
    return max(0.0, (radius - _Interval.point(deviation)).low)
