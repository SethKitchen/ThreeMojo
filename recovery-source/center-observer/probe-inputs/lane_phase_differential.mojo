# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Reconstructed source-only observer; current native qualification is pending.

Build the identical file against either source root with -I. Case logic was
recovered from retained source text; historical byte identity is not claimed.
No successor implementation, instrumentation, injected proof, or production hook.
Each invocation runs exactly one case. Float64 output is unsigned IEEE words.
Select a case with THREEMOJO_LANE_PHASE_CASE; TestSuite retains its own argv.
"""

from extensions.carla.curve_bounds import (
    _lane_jet,
    _scaled_point_distance_jet,
    _expansion_distance_jet,
)
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.curve_frozen_arc import _frozen_arc_context
from extensions.carla.geometry import ARC, LINE, PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneCertificate,
    _LaneExclusionGoal,
    _checked_center,
    _continue_lane_certificate,
    _expansion_center,
    _goal_excludes,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _run_lane_search,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LaneId, RoadInfoGeometry
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.memory import bitcast
from std.os import getenv
from std.testing import TestSuite, assert_equal, assert_true
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate
from tests._spiral_acceptance_controls import (
    _acceptance_road,
    _capture_acceptance_proof,
    _assert_acceptance_hit,
)
from tests.test_carla_cross_candidate_certificates import _road
from tests.test_carla_lane_proof_fallback_residuals import _external_goal, _loose
from tests.test_spiral_lazy_taylor_paths import _enlarge
from tests.test_carla_arc_frozen_constants import _map as _arc_map


def _word(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _dump_cell(label: String, index: Int, cell: _ClosedInterval):
    print(label, index, _word(cell.low), _word(cell.high), cell.depth,
          _word(cell.lower), _word(cell.scale))


def _dump(label: String, certificate: _LaneCertificate):
    print("CERT", label, _word(certificate.s), _word(certificate.point[0]),
          _word(certificate.point[1]), _word(certificate.point[2]),
          _word(certificate.scale), _word(certificate.lower),
          _word(certificate.upper), certificate.exact_witness,
          certificate.nodes, certificate.terms, len(certificate.cells))
    for i in range(len(certificate.cells)):
        _dump_cell("CELL", i, certificate.cells[i])


def _result(message: String, before_nodes: Int, before_terms: Int,
            certificate: _LaneCertificate):
    # Length precedes the complete error text; do not normalize or trim it.
    print("STATUS", "ok" if message == "" else "exception")
    print("ERROR", message.byte_length(), message)
    print("DELTA", certificate.nodes - before_nodes,
          certificate.terms - before_terms)
    _dump("after", certificate)


def _observe_run(
    road: Road,
    low: Float64,
    high: Float64,
    location: Vector3,
    mut certificate: _LaneCertificate,
    pending: List[Tuple[Float64, Float64, Int]],
    requested_gap: Optional[Tuple[Float64, Float64]] = None,
    max_nodes: Int = 200,
    max_terms: Int = 20000,
    max_depth: Int = 96,
    proof: Optional[_SpiralDomainProof] = None,
    goal: Optional[_LaneExclusionGoal] = None,
    external: Optional[Array[Float64, 3]] = None,
    terminal: List[_ClosedInterval] = List[_ClosedInterval](),
    lane: Int = 0,
) raises -> String:
    _dump("before", certificate)
    print("LIMITS", max_nodes, max_terms, max_depth)
    print("PENDING", len(pending))
    for i in range(len(pending)):
        print("TASK", i, _word(pending[i][0]), _word(pending[i][1]), pending[i][2])
    print("TERMINAL", len(terminal))
    for i in range(len(terminal)):
        _dump_cell("INPUT_CELL", i, terminal[i])
    var before_nodes = certificate.nodes
    var before_terms = certificate.terms
    var message = String("")
    try:
        _run_lane_search(road, 0, lane, low, high, location, certificate,
                         pending.copy(), _ClosedIntervals(), terminal.copy(),
                         requested_gap, max_nodes, max_terms, max_depth,
                         proof, goal, external)
    except error:
        message = String(error)
    _result(message, before_nodes, before_terms, certificate)
    return message


def _refine_case(kind: Int) raises:
    var road = _diagonal_road(kind == 4)
    var location = Vector3(0.4, Float32(0.0) if kind == 4 else Float32(1.0), 0.6)
    var selected = _capture_acceptance_proof(road, 0.4, 0.7)
    if kind == 2:
        selected = _enlarge(selected)
    elif kind == 5:
        selected = _enlarge(selected, 512.0)
    if kind != 3:
        _assert_acceptance_hit(road, 0.4, 0.7, selected)
    else:
        selected.record_at = 1
    var proof: Optional[_SpiralDomainProof] = selected
    if kind == 0:
        proof = None
    # The fixture's ordinary invocation, including its standard defaults.
    var certificate = _refine_lane_certificate(
        road, 0, 0, 0.4, 0.7, location, 0.7, 0.0, spiral_proof=proof
    )
    _result("", 0, 0, certificate)
    assert_equal(certificate.nodes, 3 if kind == 2 else 2)
    assert_equal(certificate.terms, 506 if kind == 2 else 480)


def _partition_case(interior: Bool, max_nodes: Int = 200,
                    reverse: Bool = False) raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6) if interior else Vector3(0, 1, 0)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    _assert_acceptance_hit(road, 0.4, 0.7, proof)
    var pending = List[Tuple[Float64, Float64, Int]]()
    if interior:
        # pop() visits the interior first. The alternate valid cover changes
        # that order; compare each variant old-to-new, never to one another.
        if reverse:
            pending.append((0.51, 0.59, 0))
            pending.append((0.59, 0.7, 0))
            pending.append((0.4, 0.51, 0))
        else:
            pending.append((0.4, 0.51, 0))
            pending.append((0.59, 0.7, 0))
            pending.append((0.51, 0.59, 0))
    else:
        pending.append((0.4, 0.55, 0))
        pending.append((0.55, 0.7, 0))
    var seed = Float64(0.5) if interior else Float64(0.4)
    var certificate = _whole_certificate(road, location, 0.4, 0.7, seed)
    var message = _observe_run(road, 0.4, 0.7, location, certificate, pending,
                              max_nodes=max_nodes, proof=proof)
    if max_nodes == 200:
        assert_equal(message, "")
    else:
        assert_true(message == "" or message ==
                    "Lane refinement exhausted its interval work limit")


def _goal_case(kind: Int) raises:
    var road = _diagonal_road()
    var location = Vector3(0, 1, 0) if kind == 3 else Vector3(0.4, 1, 0.6)
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    if kind == 1:
        proof.record_at = 1
    elif kind >= 2:
        proof = _loose(proof)
        _assert_acceptance_hit(road, 0.4, 0.7, proof)
    var external = _external_goal(road, location, 0.4 if kind == 3 else 0.5)
    var certificate = _whole_certificate(road, location)
    _dump("before", certificate)
    print("GOAL", _word(external[0].upper), _word(external[0].scale),
          external[0].allow_equal)
    print("EXTERNAL", _word(external[1][0]), _word(external[1][1]),
          _word(external[1][2]))
    var before_nodes = certificate.nodes
    var before_terms = certificate.terms
    var message = String("")
    try:
        _continue_lane_certificate(
            road, 0, 0, 0.4, 0.7, location, certificate, None, 1.0,
            max_nodes=100, max_terms=10000, spiral_proof=proof,
            goal=external[0], external_witness=external[1].copy()
        )
    except error:
        message = String(error)
    _result(message, before_nodes, before_terms, certificate)
    print("GOAL_EXCLUDES", _goal_excludes(certificate.lower, certificate.scale,
                                         external[0]))
    assert_equal(message, "")
    assert_true(_goal_excludes(certificate.lower, certificate.scale, external[0]))


def _resume_case(kind: Int) raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    var enlarged = kind == 2 or kind == 3 or kind == 7 or kind == 8
    if enlarged:
        proof = _enlarge(proof)
    var total = 500 if enlarged else 480
    var max_terms = total
    var max_nodes = 3
    if kind == 1 or kind == 3:
        max_terms -= 1
    elif kind == 4:
        max_terms = 480
    elif kind == 5 or kind == 7:
        max_terms = 489
    elif kind == 6:
        max_terms = 490
    elif kind == 8:
        max_nodes = 2
    var certificate = _whole_certificate(road, location)
    _dump("before", certificate)
    print("LIMITS", max_nodes, max_terms, 96)
    var before_nodes = certificate.nodes
    var before_terms = certificate.terms
    var message = String("")
    try:
        _resume_lane_certificate(
            road, 0, 0, 0.4, 0.7, location, certificate, 1000000.0, 1.0,
            max_nodes=max_nodes, max_terms=max_terms, spiral_proof=proof
        )
    except error:
        message = String(error)
    _result(message, before_nodes, before_terms, certificate)
    if kind == 1 or kind == 3 or kind == 7:
        assert_equal(message, "Lane refinement exhausted its quadrature work limit")
    elif kind == 8:
        assert_equal(message, "Lane refinement exhausted its interval work limit")
    else:
        assert_equal(message, "")
    # One-short cases also expose a legitimate second invocation and its
    # cumulative ledger. Preserve the failed certificate; do not reseed it.
    if kind == 1 or kind == 3:
        var spent = certificate.terms
        print("RESUME_AFTER_EXCEPTION")
        _dump("before-resume", certificate)
        before_nodes = certificate.nodes
        before_terms = certificate.terms
        message = ""
        try:
            _resume_lane_certificate(
                road, 0, 0, 0.4, 0.7, location, certificate, 1000000.0, 1.0,
                max_nodes=5, max_terms=spent + total - 10, spiral_proof=proof
            )
        except error:
            message = String(error)
        _result(message, before_nodes, before_terms, certificate)
        assert_equal(message, "")


def _depth_case() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var certificate = _whole_certificate(road, location)
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.4, 0.7, 0)]
    var message = _observe_run(
        road, 0.4, 0.7, location, certificate, pending,
        (Float64(0.0), Float64(1.0)), 100, 10000, 0, proof
    )
    assert_equal(message, "Lane refinement exhausted its numerical accuracy limit")


def _cache_case(spiral: Bool, seed_at_center: Bool) raises:
    # Exact fixture from test_carla_lane_cache_scale_residuals.
    var road = _acceptance_road()
    if not spiral:
        road.info.geometries[0].geometry.kind = LINE
    var center = Float64(0.6875)
    var step = _next_up(center) - center
    var first_root = center - 8.0 * step
    var magnitude = bitcast[DType.float64](UInt64(1127) << UInt64(52))
    road.info.elevations[0].polynomial = CubicPolynomial(
        magnitude * first_root * center, -magnitude * (first_root + center),
        magnitude, 0.0, 0.0
    )
    var terms = 0
    var at_center = _checked_center(road, 0, 0, center, terms, 100)
    road.info.geometries[0].geometry.x -= at_center[0]
    var low = _next_down(center)
    var high = _next_up(_next_up(_next_up(center)))
    var proof: Optional[_SpiralDomainProof] = None
    if spiral:
        proof = _capture_acceptance_proof(road, low, high)
    var qx = Float64(-1.3877787807814457e-17)
    var qy = Float64(7.888609052210118e-31)
    var location = Vector3(Float32(qx), Float32(qy), 0)
    var query: Array[Float64, 3] = [qx, qy, 0.0]
    var external_road = _road()
    external_road.info.geometries[0].geometry.x = qx
    terms = 0
    var external = _checked_center(external_road, 0, 0, 0.0, terms, 100)
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    var seed = center if seed_at_center else low
    var certificate = _whole_certificate(road, location, low, high, seed)
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    var message = _observe_run(
        road, low, high, location, certificate, pending,
        (Float64(0.0), Float64(1.0)), 100, 20000, 1, proof, goal, external.copy()
    )
    assert_equal(message, "Lane refinement exhausted its numerical accuracy limit")
    assert_equal(certificate.s, center)


def _frozen_headroom(kind: Int) raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.curvature_start = 0.125
    var location = Vector3(0, 0, 0)
    var certificate = _whole_certificate(road, location, 1.0, 1.0, 1.0)
    var max_nodes = 1 if kind == 0 else 100
    var max_terms = certificate.terms + 1 if kind == 1 else 100
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(1.0, 1.0, 0, certificate.lower, certificate.scale)
    ]
    var message = _observe_run(
        road, 1.0, 1.0, location, certificate,
        List[Tuple[Float64, Float64, Int]](), max_nodes=max_nodes,
        max_terms=max_terms, terminal=terminal
    )
    assert_equal(message, "")
    assert_true(certificate.exact_witness)
    assert_equal(certificate.nodes, 1 if kind == 2 else 0)


def _frozen_active() raises:
    # Same admitted constant ARC owner and query as the frozen-model suite.
    # Bounded depth forces a short observable call if zero gap cannot close.
    var map = _arc_map()
    ref road = map.roads[0]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var location = Vector3(80.0, bitcast[DType.float32](UInt32(0x415599A0)), 0.0)
    var low = Float64(24.75)
    var high = Float64(25.0)
    var context = _frozen_arc_context(road, 0, lane, low, high)
    assert_true(Bool(context))
    # The fixture helper fixes lane=0. This map includes lane 0, so construct
    # the same genuine whole-domain certificate with the driving lane here.
    var terms = 0
    var point = _checked_center(road, 0, lane, high, terms, 100)
    var query: Array[Float64, 3] = [Float64(location.x), Float64(location.y), 0.0]
    var scale = _point_gap_scale(point, query)
    var cells: List[_ClosedInterval] = [_ClosedInterval(low, high, 0, 0.0, scale)]
    var certificate = _LaneCertificate(
        high, point.copy(), scale, 0.0,
        _refinement_square[3](point, query, scale).high, False, cells^, 0, terms
    )
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    var message = _observe_run(
        road, low, high, location, certificate, pending,
        (Float64(0.0), Float64(1.0)), 20, 2000, 0, lane=lane
    )
    assert_true(message == "" or message ==
                "Lane refinement exhausted its numerical accuracy limit")


def _support_case(depth: Int) raises:
    # Same support-depth fixture, but the competing point is checked on an
    # actual second road rather than supplied by modifying a witness array.
    var road = _road()
    road.info.geometries[0].geometry.x = 0.1
    var location = Vector3(-1, 0, 0)
    var query: Array[Float64, 3] = [-1.0, 0.0, 0.0]
    var terms = 0
    var nearest = _checked_center(road, 0, 0, 1.0, terms, 100)
    var other = _road(2)
    other.info.geometries[0].geometry.x = _next_down(nearest[0])
    terms = 0
    var external = _checked_center(other, 0, 0, 0.0, terms, 100)
    assert_equal(_word(external[0]), _word(_next_down(nearest[0])))
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    # Inspect genuine producer output separately; this is not a substituted
    # solver result. It proves the selected input has a proper support cut.
    var incumbent_scale = _point_gap_scale(nearest, query)
    var center_s = _expansion_center(1.0, 2.0, 1.0)
    var domain = _scaled_point_distance_jet(
        _lane_jet(road, 0, 0, 1.0, 2.0), location, incumbent_scale
    )
    var center = _expansion_distance_jet(road, 0, 0, center_s, location,
                                         incumbent_scale)
    var support = _minimizer_support(domain, center, center_s, 1.0, 1.0, 2.0)
    print("SUPPORT", _word(support.low), _word(support.high))
    assert_true(support.high < 2.0)
    var certificate = _whole_certificate(road, location, 1.0, 2.0, 2.0)
    var pending: List[Tuple[Float64, Float64, Int]] = [(1.0, 2.0, 0)]
    var message = _observe_run(
        road, 1.0, 2.0, location, certificate, pending,
        (Float64(0.0), Float64(1.0)), 100, 1000, depth, None, goal,
        external.copy()
    )
    if depth == 0:
        assert_equal(message, "Lane refinement exhausted its numerical accuracy limit")
        assert_equal(certificate.nodes, 1)
    else:
        assert_true(message == "" or message ==
                    "Lane refinement exhausted its numerical accuracy limit")


def _sampled_case(depth: Int, first_cell: Int) raises:
    # Fixture pattern from test_carla_lane_order_successor._case; only the
    # existing production entry is called, never the reference implementation.
    var road = _road()
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 3.0)
    for i in range(4):
        var x = Float64(-1.0 if i % 2 == 0 else 1.0)
        geometry.samples.append(_Sample(x, 0.0, Float64(i), 1.0, 0.0))
    road.length = 3.0
    road.info.geometries[0] = RoadInfoGeometry(0.0, geometry^)
    var location = Vector3(0, 1, 0)
    var seed = Float64(0.5)
    var pending = List[Tuple[Float64, Float64, Int]]()
    if first_cell == 0:
        pending.append((0.1, 2.9, 0))
    else:
        pending.append((0.1, 1.1, 0))
        pending.append((1.1, 2.9, 0))
        seed = 1.5
    var certificate = _whole_certificate(road, location, 0.1, 2.9, seed)
    var message = _observe_run(
        road, 0.1, 2.9, location, certificate, pending,
        (Float64(0.0), Float64(1.0)), 100, 10000, depth
    )
    assert_equal(message, "Lane refinement exhausted its numerical accuracy limit")


def _case_names() -> List[String]:
    return [
        "ordinary-no-proof", "cached-proof", "enlarged-proof", "stale-proof",
        "thin-width-proof", "above-eager-threshold",
        "grouped-endpoint-partition", "grouped-interior-partition",
        "goal-cached", "goal-stale", "goal-grouped-interior", "goal-grouped-endpoint",
        "resume-cached-exact", "resume-cached-one-short",
        "resume-enlarged-exact", "resume-enlarged-one-short",
        "headroom-480", "headroom-489", "headroom-490",
        "enlarged-headroom-489", "node-one-short", "depth-zero-grouped",
        "cache-line-edge-seed", "cache-line-center-seed",
        "cache-spiral-edge-seed", "cache-spiral-center-seed",
        "frozen-node-headroom", "frozen-term-headroom", "frozen-full-headroom",
        "frozen-active-zero-gap", "support-depth-0", "support-depth-1", "support-depth-2",
        "sampled-depth-0", "sampled-depth-1", "sampled-depth-3",
        "sampled-partition-depth-1",
        "order-prefix-1", "order-prefix-2", "order-prefix-3",
        "order-prefix-4", "order-prefix-5", "order-prefix-6",
        "order-reversed-prefix-1", "order-reversed-prefix-2",
        "order-reversed-prefix-3", "order-reversed-prefix-4",
        "order-reversed-prefix-5", "order-reversed-prefix-6",
    ]


def test_selected_case() raises:
    var names = _case_names()
    var requested = getenv("THREEMOJO_LANE_PHASE_CASE", "")
    var chosen = -1
    for i in range(len(names)):
        if names[i] == requested:
            chosen = i
    if chosen < 0:
        raise Error("Unknown differential case: " + requested)
    print("CASE", requested)
    if chosen < 6:
        _refine_case(chosen)
    elif chosen < 8:
        _partition_case(chosen == 7)
    elif chosen < 12:
        _goal_case(chosen - 8)
    elif chosen < 21:
        _resume_case(chosen - 12)
    elif chosen == 21:
        _depth_case()
    elif chosen < 26:
        _cache_case(chosen >= 24, chosen % 2 == 1)
    elif chosen < 29:
        _frozen_headroom(chosen - 26)
    elif chosen == 29:
        _frozen_active()
    elif chosen < 33:
        _support_case(chosen - 30)
    elif chosen < 36:
        _sampled_case(3 if chosen == 35 else chosen - 33, 0)
    elif chosen == 36:
        _sampled_case(1, 1)
    elif chosen < 43:
        _partition_case(True, chosen - 36)
    else:
        _partition_case(True, chosen - 42, True)
    print("END", requested)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
