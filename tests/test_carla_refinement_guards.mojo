# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals and edge branches of the certified lane-distance solver."""

from extensions.carla.curve_bounds import (
    _expansion_distance_jet,
    _lane_jet_with_proof,
    _scaled_point_distance_box,
    _scaled_point_distance_jet,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.lane_distance import (
    _point_gap_scale,
    _refinement_square as _normalized_square,
)
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.geometry import (
    ARC,
    LINE,
    POLY3,
    SPIRAL,
    RoadGeometry,
    RoadGeometryKind,
    _Sample,
    with_arc,
    with_spiral,
)
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneCertificate,
    _LaneExclusionGoal,
    _ProofNodeWork,
    _axis_lane_minimum,
    _checked_center,
    _continue_lane_certificate,
    _expansion_center,
    _finish_lane_certificate,
    _global_lower,
    _lane_certificate_contains,
    _lane_certificate_dominates_cells,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _rounded_axis_lane_minimum,
    _run_lane_search,
    _subdivided_lane_box_with_nodes,
    _try_rounded_arc_witness,
)
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
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate
from tests._spiral_acceptance_controls import _capture_acceptance_proof
from tests.test_spiral_lazy_taylor_paths import _enlarge


def _next_up(value: Float64) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](value) + 1)


def _next_down(value: Float64) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](value) - 1)


def _road(
    kind: RoadGeometryKind = LINE,
    x: Float64 = 0.0,
    start: Float64 = 0.0,
    length: Float64 = 20.0,
    heading: Float64 = 0.0,
    curvature: Float64 = 0.1,
    width: Float64 = 3.5,
    width_slope: Float64 = 0.0,
    width_start: Float64 = 0.0,
    offset_slope: Float64 = 0.0,
    geometries: Int = 1,
    offsets: Int = 1,
    elevations: Int = 1,
) raises -> Road:
    """Build one section with lanes -1, 0 and 1."""
    var road = Road(
        RoadId(1),
        "refine",
        start + length,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), min(start, 0.0))
    for id in [-1, 0, 1]:
        var lane = road.sections[0].add_lane(LaneId(id))
        road.sections[0].lanes[lane].type = LANE_DRIVING
        if id != 0:
            road.sections[0].lanes[lane].info.widths.append(
                RoadInfoLaneWidth(
                    width_start,
                    CubicPolynomial(width, width_slope, 0, 0, width_start),
                )
            )
    var base = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var geometry = base^
    if kind == ARC:
        geometry = with_arc(geometry^, curvature)
    elif kind == SPIRAL:
        geometry = with_spiral(geometry^, 0.0, curvature)
    elif kind == POLY3:
        geometry.kind = POLY3
        for i in range(5):
            var s = Float64(i) * length / 4.0
            geometry.samples.append(_Sample(s, 0.0, s, 1.0, 0.0))
    geometry.x = x
    geometry.heading = heading
    geometry.length = length / Float64(geometries)
    for i in range(geometries):
        geometry.s = start + Float64(i) * geometry.length
        road.info.geometries.append(
            RoadInfoGeometry(geometry.s, geometry.copy())
        )
    for i in range(offsets):
        road.info.lane_offsets.append(
            RoadInfoLaneOffset(
                Float64(i) * 5.0 + min(start, 0.0),
                CubicPolynomial(0, offset_slope, 0, 0, 0),
            )
        )
    for i in range(elevations):
        road.info.elevations.append(
            RoadInfoElevation(
                Float64(i) * 5.0 + min(start, 0.0),
                CubicPolynomial(0, 0, 0, 0, 0),
            )
        )
    return road^


def _lane(road: Road, id: Int = -1) raises -> Int:
    return road.sections[0].lane_index(LaneId(id))


def _query(location: Vector3) -> Array[Float64, 3]:
    return [Float64(location.x), Float64(location.y), Float64(location.z)]


def _certificate(
    road: Road,
    lane: Int,
    s: Float64,
    cells: List[_ClosedInterval],
    upper: Float64 = 4.0,
    exact: Bool = False,
) raises -> _LaneCertificate:
    var terms = 0
    var point = _checked_center(road, 0, lane, s, terms, 1000000)
    return _LaneCertificate(
        s, point^, 1.0, 0.0, upper, exact, cells.copy(), 0, 0
    )


# --- scalar centers and axis searches -----------------------------------------


def test_checked_center_needs_a_geometry_record() raises:
    var road = _road(start=5.0)
    var terms = 0
    with assert_raises(contains="quadrature count"):
        _ = _checked_center(road, 0, _lane(road), 1.0, terms, 1000)


def test_axis_minimum_refuses_and_declines_unsupported_input() raises:
    var road = _road()
    var origin = Vector3(5, 0, 0)
    with assert_raises(contains="finite nonnegative"):
        _ = _axis_lane_minimum(road, 0, 1, nan[DType.float64](), 2.0, origin)
    var offsets = _road(offsets=2)
    assert_false(Bool(_axis_lane_minimum(offsets, 0, 1, 1.0, 2.0, origin)))
    var elevations = _road(elevations=2)
    assert_false(Bool(_axis_lane_minimum(elevations, 0, 1, 1.0, 2.0, origin)))
    # A singleton domain returns its endpoint whatever the query.
    var point = _axis_lane_minimum(road, 0, _lane(road, 0), 2.0, 2.0, origin)
    assert_equal(point.value()[0], 2.0)


def test_axis_minimum_hits_the_query_during_bisection() raises:
    # The inverse seed misses, and a bisection station hits exactly.
    var road = _road(x=1.3, start=1.1, length=10.0)
    var query = Vector3(Float32(5.12341833114624), 0, 0)
    var found = _axis_lane_minimum(road, 0, _lane(road, 0), 1.1, 11.1, query)
    assert_equal(found.value()[2][0], Float64(query.x))


def _rounded(
    road: Road,
    low: Float64,
    high: Float64,
    query: Vector3,
    terms: Int = 0,
    max_terms: Int = 1000000,
) raises -> Bool:
    var nodes = 0
    var spent = terms
    return Bool(
        _rounded_axis_lane_minimum(
            road,
            0,
            _lane(road, 0),
            low,
            high,
            query,
            nodes,
            spent,
            1000,
            max_terms,
            96,
        )
    )


def test_rounded_axis_minimum_endpoints_hits_and_brackets() raises:
    var road = _road(x=0.1, start=0.3, length=10.0)
    with assert_raises(contains="quadrature work limit"):
        _ = _rounded(road, 0.8, 10.3, Vector3(3, 0, 0), terms=10, max_terms=10)
    assert_true(_rounded(road, 0.8, 10.3, Vector3(-5, 0, 0)))
    assert_true(_rounded(road, 2.0, 2.0, Vector3(3, 0, 0)))
    assert_true(_rounded(road, 0.8, 10.3, Vector3(50, 0, 0)))
    # Found with the real evaluator: the seed misses and a bisection
    # station hits, then a bracket whose right end is closer.
    assert_true(
        _rounded(road, 0.8, 10.3, Vector3(Float32(1.0038000345230103), 0, 0))
    )
    var shifted = _road(x=0.7, start=2.9, length=10.0)
    assert_true(
        _rounded(shifted, 3.4, 12.9, Vector3(Float32(1.8207999467849731), 0, 0))
    )


# --- certificate bookkeeping --------------------------------------------------


def test_global_lower_without_a_center_slope() raises:
    var domain = _Jet(
        _Interval(1.0, 2.0), _Interval(-1.0, 1.0), _Interval(0.0, 1.0), 0.0
    )
    var center = _Jet(
        _Interval(1.0, 1.0), _Interval.whole(), _Interval(0.0, 1.0), 0.0
    )
    assert_equal(_global_lower(domain, center, _Interval(-1.0, 1.0)), 1.0)


def test_finish_certificate_exact_witness_and_pruned_cells() raises:
    var point: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var closed = _ClosedIntervals()
    var none = List[_ClosedInterval]()
    var exact = _finish_lane_certificate(1.0, point, point, closed, none, 0, 0)
    assert_true(exact.exact_witness)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var far = _ClosedIntervals()
    far.add(_ClosedInterval(2.0, 3.0, 0, 1000.0, 1.0))
    with assert_raises(contains="lost its possible minimizing cells"):
        _ = _finish_lane_certificate(1.0, point, query, far, none, 0, 0)
    var kept = _ClosedIntervals()
    kept.add(_ClosedInterval(2.0, 3.0, 0, 0.0, 1.0))
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(4.0, 4.0, 0, 1000.0, 1.0)
    ]
    var finished = _finish_lane_certificate(
        1.0, point, query, kept, terminal, 0, 0
    )
    assert_equal(len(finished.cells), 1)


def test_cell_dominance_for_a_later_candidate() raises:
    var near: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var farther: Array[Float64, 3] = [3.0, 0.0, 0.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var one = _LaneCertificate(
        0.0, near^, 1.0, 0.5, 1.5, False, List[_ClosedInterval](), 0, 0
    )
    var cells: List[_ClosedInterval] = [_ClosedInterval(1.0, 2.0, 0, 5.0, 1.0)]
    var two = _LaneCertificate(
        0.0, farther^, 1.0, 5.0, 9.5, False, cells^, 0, 0
    )
    assert_true(_lane_certificate_dominates_cells(one, 2, two, 1, query))


# --- classification -----------------------------------------------------------


def test_classification_needs_width_records_and_cells() raises:
    var late = _road(width_start=3.0)
    var lane = _lane(late)
    var query = Vector3(1, 0, 0)
    var exact = _certificate(
        late, lane, 3.5, List[_ClosedInterval](), exact=True
    )
    exact.s = 1.0
    with assert_raises(contains="width record"):
        _ = _lane_certificate_contains(late, 0, lane, query, exact)
    var road = _road()
    var empty = _certificate(road, _lane(road), 1.0, List[_ClosedInterval]())
    with assert_raises(contains="possible minimizing cells"):
        _ = _lane_certificate_contains(road, 0, _lane(road), query, empty)
    var cells: List[_ClosedInterval] = [_ClosedInterval(3.0, 4.0, 0, 0.0, 1.0)]
    var missing = _certificate(late, lane, 3.5, cells)
    missing.s = 1.0
    with assert_raises(contains="width record"):
        _ = _lane_certificate_contains(late, 0, lane, query, missing)


def _edge(road: Road, cells: List[_ClosedInterval]) raises -> _LaneCertificate:
    # The query sits on the lane's edge, half a width from its center.
    return _certificate(road, _lane(road), 5.0, cells, upper=3.1)


def test_classification_limits_and_unresolved_cells() raises:
    var road = _road()
    var lane = _lane(road)
    var query = Vector3(5, 0, 0)
    var wide: List[_ClosedInterval] = [_ClosedInterval(1.0, 9.0, 0, 0.0, 1.0)]
    var limited = _edge(road, wide)
    with assert_raises(contains="interval work limit"):
        _ = _lane_certificate_contains(
            road, 0, lane, query, limited, max_nodes=1
        )
    var one = _next_up(1.0)
    var adjacent: List[_ClosedInterval] = [
        _ClosedInterval(one, _next_up(one), 0, 0.0, 1.0)
    ]
    var tied = _edge(road, adjacent)
    with assert_raises(contains="unresolved"):
        _ = _lane_certificate_contains(road, 0, lane, Vector3(1, 0, 0), tied)
    var deep: List[_ClosedInterval] = [_ClosedInterval(4.0, 6.0, 96, 0.0, 1.0)]
    var bottom = _edge(road, deep)
    with assert_raises(contains="unresolved"):
        _ = _lane_certificate_contains(road, 0, lane, query, bottom)


def test_classification_skips_far_cells_and_refuses_split_records() raises:
    var road = _road()
    var lane = _lane(road)
    var query = Vector3(5, 0, 0)
    var far: List[_ClosedInterval] = [_ClosedInterval(15.0, 16.0, 0, 0.0, 1.0)]
    var skipped = _edge(road, far)
    _ = _lane_certificate_contains(road, 0, lane, query, skipped)
    var split = _road(geometries=2)
    var across: List[_ClosedInterval] = [
        _ClosedInterval(9.0, 11.0, 0, 0.0, 1.0)
    ]
    var crossing = _certificate(split, _lane(split), 10.0, across, upper=3.1)
    with assert_raises(contains="minimizing cell"):
        _ = _lane_certificate_contains(
            split, 0, _lane(split), Vector3(10, 0, 0), crossing
        )
    # A width that changes sign across the cell cannot classify directly.
    var signed = _road(width=-1.0, width_slope=1.0)
    var cells: List[_ClosedInterval] = [_ClosedInterval(0.5, 1.5, 0, 0.0, 1.0)]
    var unsure = _certificate(signed, _lane(signed), 1.0, cells, upper=3.1)
    try:
        _ = _lane_certificate_contains(
            signed, 0, _lane(signed), Vector3(1, 0, 0), unsure
        )
    except:
        pass


# --- refinement entry ---------------------------------------------------------


def test_refinement_entry_refuses_bad_domains_and_budgets() raises:
    var road = _road()
    var lane = _lane(road)
    var at = Vector3(5, 2, 0)
    var bad = nan[DType.float64]()
    for which in range(3):
        var low = bad if which == 0 else 1.0
        var high = bad if which == 1 else 2.0
        var seed = bad if which == 2 else 1.5
        with assert_raises(contains="finite parameter bounds"):
            _ = _refine_lane_certificate(
                road, 0, lane, low, high, at, seed, 0.0
            )
    for which in range(3):
        var low = 2.0 if which == 0 else 1.0
        var high = 1.0 if which == 0 else 2.0
        var seed = 0.5 if which == 1 else (3.0 if which == 2 else 1.5)
        with assert_raises(contains="outside its parameter interval"):
            _ = _refine_lane_certificate(
                road, 0, lane, low, high, at, seed, 0.0
            )
    var negative = _road(start=-5.0, length=20.0, width_start=-5.0)
    _ = _refine_lane_certificate(
        negative, 0, _lane(negative), -1.0, 1.0, Vector3(0, 2, 0), 0.0, 0.0
    )
    # A varying lane offset declines both axis proofs after one node.
    var sloped = _road(offset_slope=0.01)
    with assert_raises(contains="interval work limit"):
        _ = _refine_lane_certificate(
            sloped,
            0,
            _lane(sloped),
            1.0,
            2.0,
            at,
            1.5,
            0.0,
            max_nodes=1,
            seed_only=True,
        )
    with assert_raises(contains="interval work limit"):
        _ = _refine_lane_certificate(
            sloped, 0, _lane(sloped), 2.0, 2.0, at, 2.0, 0.0, max_nodes=1
        )


def test_rounded_arc_witness_declines_mismatches_and_adjacent_cells() raises:
    var road = _road(kind=ARC)
    var lane = _lane(road)
    var query = _query(Vector3(3, 3, 0))
    var cells: List[_ClosedInterval] = [_ClosedInterval(1.0, 2.0, 0, 0.0, 1.0)]
    var wrong = _certificate(road, lane, 1.0, cells)
    wrong.point[0] += 1.0
    assert_false(
        _try_rounded_arc_witness(
            road, 0, lane, 1.0, 2.0, query, wrong, 1000, 100000, 96
        )
    )
    # A cell that reaches the record's end has no stable interior box.
    var end = _certificate(road, lane, 19.0, cells)
    assert_false(
        _try_rounded_arc_witness(
            road, 0, lane, 19.0, 20.0, query, end, 1000, 100000, 96
        )
    )
    var one = _next_up(1.0)
    var adjacent = _certificate(road, lane, 1.0, cells)
    assert_false(
        _try_rounded_arc_witness(
            road, 0, lane, 1.0, one, query, adjacent, 1000, 100000, 96
        )
    )
    # Here the midpoint of two adjacent stations rounds up to the high one.
    var two = _next_up(one)
    var upper = _certificate(road, lane, one, cells)
    assert_false(
        _try_rounded_arc_witness(
            road, 0, lane, one, two, query, upper, 1000, 100000, 96
        )
    )


# --- resumption ---------------------------------------------------------------


def test_resumption_refuses_each_invalid_state() raises:
    var road = _road()
    var lane = _lane(road)
    var at = Vector3(5, 2, 0)
    var bad = nan[DType.float64]()
    var cells: List[_ClosedInterval] = [_ClosedInterval(1.0, 2.0, 0, 0.0, 1.0)]
    var base = _certificate(road, lane, 1.5, cells)
    for which in range(3):
        var low = bad if which == 0 else (3.0 if which == 2 else 1.0)
        var high = bad if which == 1 else 2.0
        var copy = base.copy()
        with assert_raises(contains="finite ordered"):
            _resume_lane_certificate(
                road, 0, lane, low, high, at, copy, 0.0, 1.0
            )
        with assert_raises(contains="finite ordered"):
            _continue_lane_certificate(
                road, 0, lane, low, high, at, copy, 0.0, 1.0
            )
    for gap in [bad, -1.0]:
        var copy = base.copy()
        with assert_raises(contains="nonnegative gap"):
            _continue_lane_certificate(
                road, 0, lane, 1.0, 2.0, at, copy, gap, 1.0
            )
    for s in [bad, 0.5, 3.0]:
        var copy = base.copy()
        copy.s = s
        with assert_raises(contains="outside its parameter interval"):
            _continue_lane_certificate(
                road, 0, lane, 1.0, 2.0, at, copy, 0.0, 1.0
            )
    for which in range(2):
        var copy = base.copy()
        if which == 0:
            copy.nodes = -1
        else:
            copy.terms = -1
        with assert_raises(contains="nonnegative consumed work"):
            _continue_lane_certificate(
                road, 0, lane, 1.0, 2.0, at, copy, 0.0, 1.0
            )
    var empty = base.copy()
    empty.cells.clear()
    with assert_raises(contains="possible minimizing cells"):
        _continue_lane_certificate(road, 0, lane, 1.0, 2.0, at, empty, 0.0, 1.0)
    var outside: List[_ClosedInterval] = [
        _ClosedInterval(bad, 2.0, 0, 0.0, 1.0),
        _ClosedInterval(1.0, bad, 0, 0.0, 1.0),
        _ClosedInterval(0.5, 2.0, 0, 0.0, 1.0),
        _ClosedInterval(1.0, 3.0, 0, 0.0, 1.0),
        _ClosedInterval(1.8, 1.2, 0, 0.0, 1.0),
    ]
    for cell in outside:
        var copy = base.copy()
        copy.cells = [cell]
        with assert_raises(contains="outside its original interval"):
            _continue_lane_certificate(
                road, 0, lane, 1.0, 2.0, at, copy, 0.0, 1.0
            )
    var negative = base.copy()
    negative.cells = [_ClosedInterval(1.0, 2.0, -1, 0.0, 1.0)]
    with assert_raises(contains="nonnegative cell depth"):
        _continue_lane_certificate(
            road, 0, lane, 1.0, 2.0, at, negative, 0.0, 1.0
        )


# --- search states ------------------------------------------------------------


def _search(
    road: Road,
    location: Vector3,
    var certificate: _LaneCertificate,
    var pending: List[Tuple[Float64, Float64, Int]],
    low: Float64 = 0.0,
    high: Float64 = 20.0,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
) raises -> _LaneCertificate:
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(certificate.s, certificate.s, 0, 0.0, 1.0)
    ]
    _run_lane_search(
        road,
        0,
        _lane(road, 0),
        low,
        high,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        terminal^,
        None,
        max_nodes,
        max_terms,
        96,
    )
    return certificate^


def test_search_skips_the_frozen_arc_without_budget() raises:
    var road = _road(kind=ARC)
    var certificate = _certificate(
        road, _lane(road, 0), 1.0, List[_ClosedInterval]()
    )
    _ = _search(road, Vector3(3, 3, 0), certificate.copy(), [], max_nodes=1)
    _ = _search(road, Vector3(3, 3, 0), certificate^, [], max_terms=1)


def test_search_tiny_cell_reaches_the_query_exactly() raises:
    # Lane 0's center at s = 0.5 is the stored point (0.5, 0, 0).
    var road = _road()
    var certificate = _certificate(
        road, _lane(road, 0), 9.0, List[_ClosedInterval]()
    )
    var found = _search(
        road, Vector3(0.5, 0, 0), certificate^, [(0.5, _next_up(0.5), 0)]
    )
    assert_true(found.exact_witness)


def test_search_adjacent_subnormal_cell_rounds_to_its_low_end() raises:
    # Lane 0's center at s = 0 is the query itself.
    var road = _road()
    var certificate = _certificate(
        road, _lane(road, 0), 9.0, List[_ClosedInterval]()
    )
    var found = _search(
        road, Vector3(0, 0, 0), certificate^, [(0.0, 5.0e-324, 0)]
    )
    assert_true(found.exact_witness)
    var off = _certificate(road, _lane(road, 0), 9.0, List[_ClosedInterval]())
    _ = _search(road, Vector3(0, 1, 0), off^, [(0.0, 5.0e-324, 0)])


def test_search_adjacent_cell_across_a_binade() raises:
    var road = _road(kind=POLY3)
    var certificate = _certificate(
        road, _lane(road, 0), 9.0, List[_ClosedInterval]()
    )
    _ = _search(
        road, Vector3(1, 1, 0), certificate^, [(_next_down(1.0), 1.0, 0)]
    )


def test_search_with_sampled_cuts_outside_the_cell() raises:
    # Samples every 5 m give cuts just past 5 and 10 inside [4, 14]. One
    # cell lies before both cuts and one after both.
    var road = _road(kind=POLY3)
    var lane = _lane(road, 0)
    # Each query lies just outside its cell, so the cell needs a split.
    var early = _certificate(road, lane, 9.0, List[_ClosedInterval]())
    _ = _search(
        road, Vector3(3.9, 1, 0), early^, [(4.2, 4.8, 0)], low=4.0, high=14.0
    )
    var late = _certificate(road, lane, 9.0, List[_ClosedInterval]())
    _ = _search(
        road, Vector3(11.5, 1, 0), late^, [(12.0, 14.0, 0)], low=4.0, high=14.0
    )


# --- subdivided boxes ---------------------------------------------------------


def test_subdivided_box_encloses_adjacent_unresolved_cells() raises:
    var split = _road(geometries=2)
    var nodes = _ProofNodeWork(1000)
    var ten = Float64(10.0)
    var box = _subdivided_lane_box_with_nodes(
        split, 0, _lane(split), _next_down(ten), ten, 100000, nodes
    )
    assert_true(box[0][0].is_finite())
    nodes = _ProofNodeWork(1000)
    var tight = _subdivided_lane_box_with_nodes(
        split, 0, _lane(split), _next_down(ten), ten, 0, nodes
    )
    assert_false(tight[0][0].is_finite())
    nodes = _ProofNodeWork(1000)
    var one = _subdivided_lane_box_with_nodes(
        split, 0, _lane(split), _next_down(ten), ten, 1, nodes
    )
    assert_false(one[0][0].is_finite())
    # A zero-rate spiral resolves counts up to 1e9 and no further, and the
    # midpoint of 1e9 and its successor rounds down to 1e9.
    var flat = _road(kind=SPIRAL, curvature=0.0, length=2.0e9)
    var billion = Float64(1.0e9)
    nodes = _ProofNodeWork(1000)
    var edge = _subdivided_lane_box_with_nodes(
        flat, 0, _lane(flat), billion, _next_up(billion), 100000, nodes
    )
    assert_false(edge[0][0].is_finite())
    var long = _road(kind=SPIRAL, curvature=1.0e-12, length=2.0e9)
    var at = Float64(1.5e9)
    nodes = _ProofNodeWork(1000)
    var unresolved = _subdivided_lane_box_with_nodes(
        long, 0, _lane(long), _next_down(at), at, 100000, nodes
    )
    assert_false(unresolved[0][0].is_finite())


# --- spiral proof searches -----------------------------------------------------


def _proof_search(
    seed: Float64,
    upper_factor: Float64,
    gap: Optional[Float64],
    depth: Int,
    narrow: Bool,
    witness: Bool,
) raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _enlarge(_capture_acceptance_proof(road, 0.4, 0.7))
    if narrow:
        proof.rounded_d = _Interval(0.55, 0.56)
    var start = _whole_certificate(road, location, seed=seed)
    var goal = _LaneExclusionGoal(
        start.upper * upper_factor, start.scale, False
    )
    var terms = 0
    var external = _checked_center(road, 0, 0, 0.55, terms, 2000000)
    try:
        if witness:
            _continue_lane_certificate(
                road,
                0,
                0,
                0.4,
                0.7,
                location,
                start,
                gap,
                1.0,
                max_depth=depth,
                spiral_proof=proof,
                goal=goal,
                external_witness=external^,
            )
        else:
            _continue_lane_certificate(
                road,
                0,
                0,
                0.4,
                0.7,
                location,
                start,
                gap,
                1.0,
                max_depth=depth,
                spiral_proof=proof,
                goal=goal,
            )
    except:
        pass


def test_proof_backed_cells_against_a_range_of_goals() raises:
    var factor = Float64(1.0 / 64.0)
    for _ in range(4):
        _proof_search(0.7, factor, 1000000.0, 96, False, False)
        factor *= 8.0


struct _Windows(Copyable, Movable):
    # Lower bounds the search computes for cell [0.55, 0.7] at scale 0.5.
    var loose: Float64
    var refreshed: Float64
    var fast: Float64
    var tightened: Float64
    var general: Float64

    def __init__(out self):
        self.loose = 0.0
        self.refreshed = 0.0
        self.fast = inf[DType.float64]()
        self.tightened = inf[DType.float64]()
        self.general = 0.0


comptime _WINDOW_SCALE = Float64(0.5)


def _incumbent(t: Float64) raises -> Array[Float64, 3]:
    # A synthetic point on the line from the query to the lane at s = 0.7.
    var road = _diagonal_road()
    var terms = 0
    var lane = _checked_center(road, 0, 0, 0.7, terms, 2000000)
    var query = _query(Vector3(0.4, 1, 0.6))
    return [
        query[0] + t * (lane[0] - query[0]),
        query[1] + t * (lane[1] - query[1]),
        query[2] + t * (lane[2] - query[2]),
    ]


def _windows(
    proof: _SpiralDomainProof, station: Float64 = 0.4
) raises -> _Windows:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var scale = _WINDOW_SCALE
    var result = _Windows()
    var old = _lane_jet_with_proof(road, 0, 0, 0.55, 0.7, 0.4, 0.7, proof)
    result.loose = _scaled_point_distance_box(old, location, scale).low
    var nodes = 0
    var spent = 0
    var grouped = _try_grouped_lane_jet(
        road, 0, 0, 0.55, 0.7, nodes, spent, 100, 2000000
    )
    var fresh = grouped.value().copy()
    result.refreshed = max(
        result.loose, _scaled_point_distance_box(fresh, location, scale).low
    )
    var center_s = _expansion_center(0.55, 0.7, station)
    var delta = _Interval(0.55, 0.7) - _Interval.point(center_s)
    var after = _scaled_point_distance_jet(fresh, location, scale)
    var center = _expansion_distance_jet(road, 0, 0, center_s, location, scale)
    result.general = max(result.refreshed, _global_lower(after, center, delta))
    var fast = _try_proof_expansion_jet(
        road, 0, 0, center_s, location, scale, 0.4, 0.7, proof
    )
    if fast:
        var before = _scaled_point_distance_jet(old, location, scale)
        result.fast = max(
            result.loose, _global_lower(before, fast.value(), delta)
        )
        result.tightened = max(
            result.refreshed, _global_lower(after, fast.value(), delta)
        )
    return result^


def _incumbent_upper(point: Array[Float64, 3]) raises -> Float64:
    var query = _query(Vector3(0.4, 1, 0.6))
    return _normalized_square[3](point, query, _WINDOW_SCALE).high


def _incumbent_at(target: Float64) raises -> Array[Float64, 3]:
    # Bisect the line for the first point whose upper bound reaches target,
    # then move one coordinate by single ULPs to meet target exactly.
    var low = 0.5
    var high = 1.0
    for _ in range(64):
        var middle = 0.5 * (low + high)
        if _incumbent_upper(_incumbent(middle)) < target:
            low = middle
        else:
            high = middle
    var point = _incumbent(high)
    for _ in range(64):
        var upper = _incumbent_upper(point)
        if upper == target:
            return point^
        if upper > target:
            point[0] = _next_up(point[0])
        else:
            point[0] = -_next_up(-point[0])
    raise Error("No incumbent meets the target bound exactly")


def _window_search(
    proof: _SpiralDomainProof,
    var point: Array[Float64, 3],
    goal_upper: Float64,
    zero_gap: Bool = False,
    witness: Bool = False,
    depth: Int = 0,
    station: Float64 = 0.4,
) raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var query = _query(location)
    var scale = _WINDOW_SCALE
    assert_equal(_point_gap_scale(point, query), scale)
    var upper = _incumbent_upper(point)
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(0.4, 0.4, 0, 0.0, scale)
    ]
    var certificate = _LaneCertificate(
        station, point^, scale, 0.0, upper, False, cells.copy(), 0, 0
    )
    var gap: Optional[Tuple[Float64, Float64]] = None
    if zero_gap:
        gap = (0.0, scale)
    var external: Optional[Array[Float64, 3]] = None
    if witness:
        external = _incumbent(0.5)
    _run_lane_search(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        certificate,
        [(0.55, 0.7, depth)],
        _ClosedIntervals(),
        cells^,
        gap,
        16384,
        2000000,
        3 if depth > 0 else 96,
        proof,
        _LaneExclusionGoal(goal_upper, scale, False),
        external,
    )
    # No lane sample beats the synthetic incumbent.
    assert_equal(certificate.s, station)


def test_proof_cells_close_inside_each_bound_window() raises:
    var road = _diagonal_road()
    var proof = _enlarge(_capture_acceptance_proof(road, 0.4, 0.7))
    var bounds = _windows(proof)
    assert_true(bounds.fast < bounds.tightened)
    var middle = 0.5 * (bounds.fast + bounds.tightened)
    var huge = Float64(1.0e300)
    # The tightened expansion first exceeds the incumbent, then the goal.
    _window_search(proof, _incumbent_at(middle), huge)
    _window_search(proof, _incumbent_at(bounds.tightened), middle)
    # The narrow proof backs neither the cell nor its expansion center, so
    # only the grouped refresh tightens the box. A zero gap keeps the cell
    # open until then.
    var narrow = proof
    narrow.rounded_d = _Interval(0.6, 0.61)
    var plain = _windows(narrow)
    assert_true(plain.loose < plain.refreshed)
    var inside = _incumbent_at(0.5 * (plain.refreshed + bounds.fast))
    _window_search(narrow, _incumbent_at(plain.loose), huge, zero_gap=True)
    _window_search(narrow, inside.copy(), plain.loose, zero_gap=True)
    # An external witness that never wins: once with no expansion, and once
    # at the depth limit when its support narrows the cell. The support
    # narrows only about an incumbent station inside the cell.
    _window_search(narrow, inside^, huge, zero_gap=True, witness=True)
    var within = _windows(proof, station=0.6)
    var last = _incumbent_at(
        max(within.general, max(within.fast, within.tightened))
    )
    with assert_raises(contains="numerical accuracy"):
        _window_search(
            proof,
            last^,
            huge,
            zero_gap=True,
            witness=True,
            depth=3,
            station=0.6,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
