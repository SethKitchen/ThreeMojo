# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact inverse selector, complete-owner frontier and cumulative-work controls."""

from extensions.carla.curve_sample_dispatch import (
    _sample_dispatch_cut,
    _sample_dispatch_predicate,
    _try_sample_dispatch_cuts,
)
from extensions.carla.curve_bounds import _sample_index
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _LaneExclusionGoal,
    _ClosedInterval,
    _ClosedIntervals,
    _run_lane_search,
    _resume_lane_certificate,
)
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)
from tests._sample_dispatch_controls import _dispatch_road
from tests._lazy_taylor_controls import _whole_certificate


def _f64(word: UInt64) -> Float64:
    return bitcast[DType.float64](word)


def _covers(certificate: _LaneCertificate, station: Float64) -> Bool:
    for cell in certificate.cells:
        if cell.low <= station and station <= cell.high:
            return True
    return False


def _yield_after_dispatch(
    road: Road, high: Float64, max_depth: Int = 96, reverse: Bool = False
) raises -> _LaneCertificate:
    var low = Float64(0.9)
    var location = Vector3(0, 0, 0)
    var seed = high
    var external_s = high - 0.025
    if reverse:
        location = Vector3(3, 0, 3)
        seed = low
        external_s = low + 0.025
    var certificate = _whole_certificate(road, location, low, high, seed)
    var external = road._lane_center(0, 0, external_s)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    _run_lane_search(
        road,
        0,
        0,
        low,
        high,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        100,
        10000,
        max_depth,
        None,
        goal,
        external.copy(),
    )
    assert_false(certificate.exact_witness)
    assert_true(_wide_point_order(certificate.point, external, query) < 0)
    return certificate^


def test_raw_cuts_match_exact_fraction_fixed_words() raises:
    # Independent Fraction fixtures include a necessary second successor.
    for fixture in [
        (
            UInt64(0),
            UInt64(4607182418800017408),
            UInt64(4611686018427387904),
            UInt64(4607182418800017409),
        ),
        (
            UInt64(4368491638549381120),
            UInt64(4607182418800017408),
            UInt64(4611686018427387904),
            UInt64(4607182418800017410),
        ),
        (
            UInt64(4626322717216342016),
            UInt64(4591870180066957722),
            UInt64(4607182418800017408),
            UInt64(4626350864714013082),
        ),
        (
            UInt64(4845873199050653696),
            UInt64(4602678819172646912),
            UInt64(4607182418800017408),
            UInt64(4845873199050653697),
        ),
        (
            UInt64(4607182418800017408),
            UInt64(4370743438363066368),
            UInt64(4372995238176751616),
            UInt64(4607182418800017409),
        ),
        (
            UInt64(4503599627370496),
            UInt64(1),
            UInt64(2),
            UInt64(4503599627370498),
        ),
        (UInt64(1), UInt64(1), UInt64(2), UInt64(3)),
        (UInt64(0), UInt64(1), UInt64(2), UInt64(2)),
        (
            UInt64(9094988921128908188),
            UInt64(1614679632300144556),
            UInt64(1619183231927515052),
            UInt64(9094988921128908189),
        ),
    ]:
        var origin = _f64(fixture[0])
        var threshold = _f64(fixture[1])
        var length = _f64(fixture[2])
        var result = _sample_dispatch_cut(origin, length, threshold)
        assert_true(Bool(result))
        assert_equal(bitcast[DType.uint64](result.value()), fixture[3])
        assert_false(
            _sample_dispatch_predicate(
                origin, length, threshold, _f64(fixture[3] - UInt64(1))
            )
        )
        assert_true(
            _sample_dispatch_predicate(
                origin, length, threshold, result.value()
            )
        )


def test_raw_guards_refuse_nonfinite_clamp_and_sign_inputs() raises:
    var nan = _f64(UInt64(0x7FF8000000000001))
    for args in [
        (Float64(-1), Float64(3), Float64(1)),
        (Float64(0), Float64(0), Float64(1)),
        (Float64(0), Float64(1), Float64(1)),
        (Float64(0), Float64(3), Float64(-1)),
        (Float64(0), Float64(3), nan),
        (inf[DType.float64](), Float64(3), Float64(1)),
        (Float64(0), inf[DType.float64](), Float64(1)),
        (Float64(1e308), Float64(1.1e308), Float64(1e308)),
        (Float64(0), Float64(3), Float64(0)),
        # Finite start, but neither remaining finite station dispatches right.
        (
            _f64(UInt64(0x7C90000000000000)),
            _f64(UInt64(0x7FEFFFFFFFFFFFFF)),
            _f64(UInt64(0x7FEFFFFFFFFFFFFE)),
        ),
    ]:
        assert_false(Bool(_sample_dispatch_cut(args[0], args[1], args[2])))


def test_one_and_two_cut_admission_preserves_exact_fallback_headroom() raises:
    var road = _dispatch_road()
    for count in [1, 2]:
        var high = 1.1 if count == 1 else 2.1
        var extra = 8 * count
        var node_reserve = 3 * count + 2
        var term_reserve = 16 * count
        # Every insufficient prefix, including the previous weaker reserve,
        # must decline before either counter is charged.
        for available in range(term_reserve):
            var nodes = 7
            var terms = 5
            assert_false(
                Bool(
                    _try_sample_dispatch_cuts(
                        road,
                        0.9,
                        high,
                        nodes,
                        terms,
                        7 + node_reserve,
                        5 + available,
                    )
                )
            )
            assert_equal(nodes, 7)
            assert_equal(terms, 5)
        var nodes = 7
        var terms = 5
        var cuts = _try_sample_dispatch_cuts(
            road,
            0.9,
            high,
            nodes,
            terms,
            7 + node_reserve,
            5 + term_reserve,
        )
        assert_true(Bool(cuts))
        assert_equal(cuts.value()[2], count)
        assert_equal(nodes, 8)
        assert_equal(terms, 5 + extra)
        assert_equal(cuts.value()[0], _next_up(Float64(1.0)))
        if count == 2:
            assert_equal(cuts.value()[1], _next_up(Float64(2.0)))
        for available in range(node_reserve):
            nodes = 7
            terms = 5
            assert_false(
                Bool(
                    _try_sample_dispatch_cuts(
                        road,
                        0.9,
                        high,
                        nodes,
                        terms,
                        7 + available,
                        5 + term_reserve,
                    )
                )
            )
            assert_equal(nodes, 7)
            assert_equal(terms, 5)


def test_invalid_caps_include_minimum_integer_without_overflow() raises:
    var road = _dispatch_road()
    var minimum = Int(-9223372036854775807) - 1
    for cap in [minimum, -1, 0, 1, 2, 3, 4]:
        var nodes = 0
        var terms = 0
        assert_false(
            Bool(
                _try_sample_dispatch_cuts(
                    road, 0.9, 1.1, nodes, terms, cap, 100
                )
            )
        )
        assert_equal(nodes, 0)
        assert_equal(terms, 0)
    for state in [(-1, 0, 100), (0, -1, 100), (0, 101, 100), (0, 0, minimum)]:
        var nodes = state[0]
        var terms = state[1]
        assert_false(
            Bool(
                _try_sample_dispatch_cuts(
                    road, 0.9, 1.1, nodes, terms, 100, state[2]
                )
            )
        )
        assert_equal(nodes, state[0])
        assert_equal(terms, state[1])


def test_endpoint_ownership_and_disjoint_station_coverage() raises:
    var road = _dispatch_road()
    var boundaries = road._lane_record_boundaries(0)
    var cut = _next_up(Float64(1.0))
    for endpoints in [
        (Float64(0.9), Float64(1.0)),
        (cut, Float64(1.1)),
        (Float64(0.0), Float64(1.1)),
    ]:
        var nodes = 0
        var terms = 0
        assert_false(
            Bool(
                _try_sample_dispatch_cuts(
                    road, endpoints[0], endpoints[1], nodes, terms, 100, 100
                )
            )
        )
        assert_equal(nodes, 0)
        assert_equal(terms, 0)
    var nodes = 0
    var terms = 0
    var found = _try_sample_dispatch_cuts(road, 1.0, cut, nodes, terms, 5, 16)
    assert_true(Bool(found))
    assert_equal(found.value()[0], cut)
    for offset in range(9):
        var station = _f64(
            bitcast[DType.uint64](cut) + UInt64(offset) - UInt64(4)
        )
        var left = station <= _next_down(cut)
        var right = station >= cut
        assert_true(left != right)
        assert_equal(
            _sample_index(road.info.geometries[0].geometry, station),
            0 if left else 1,
        )
    var after = road._lane_record_boundaries(0)
    assert_equal(len(boundaries), len(after))
    for i in range(len(boundaries)):
        assert_equal(
            bitcast[DType.uint64](boundaries[i]),
            bitcast[DType.uint64](after[i]),
        )


def test_unrepresentable_intermediate_sample_piece_declines_but_keeps_debit() raises:
    var road = _dispatch_road(9007199254740992.0)
    road.info.geometries[0].geometry.samples[1].s = 0.25
    road.info.geometries[0].geometry.samples[2].s = 0.5
    var low = Float64(9007199254740992.0)
    var high = _next_up(low)
    var nodes = 0
    var terms = 0
    assert_false(
        Bool(_try_sample_dispatch_cuts(road, low, high, nodes, terms, 8, 32))
    )
    assert_equal(nodes, 1)
    assert_equal(terms, 16)


def test_unavailable_split_depth_spends_no_optional_setup_work() raises:
    var road = _dispatch_road()
    var result = _yield_after_dispatch(road, 1.1, 0)
    assert_equal(result.nodes, 1)
    assert_equal(result.terms, 2)
    assert_equal(len(result.cells), 1)
    assert_equal(result.cells[0].low, 0.9)
    assert_equal(result.cells[0].high, 1.1)
    assert_equal(result.cells[0].depth, 0)


def test_original_cheap_goal_yield_precedes_optional_setup() raises:
    var road = _dispatch_road()
    for reverse in [False, True]:
        var result = _yield_after_dispatch(road, 1.1, 96, reverse)
        assert_equal(len(result.cells), 1)
        assert_equal(result.cells[0].low, 0.9)
        assert_equal(result.cells[0].high, 1.1)
        assert_equal(result.cells[0].depth, 0)
        assert_equal(result.nodes, 1)
        assert_equal(result.terms, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
