# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded resume controls for retained Float64 candidate domains."""

from extensions.carla.curve_distance import (
    _normalized_square,
    _wide_point_order,
)
from extensions.carla.curve_interval import _next_up
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _LaneCertificate,
    _next_resume_gap,
    _rebase_lower,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _scaled_accuracy,
    _search_accuracy,
)
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _sampled_road


def _three_point_certificate(
    road: Road, scale: Float64 = 4.0
) raises -> _LaneCertificate:
    var low = Float64(0.5)
    var high = _next_up(_next_up(low))
    var point = road._lane_center(0, 0, low)
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _normalized_square[3](point, zero, scale).high
    # This is a valid loose cover of exactly three parameters. The retained
    # depth and spent work simulate an exported nonterminal search state.
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(low, high, 7, 0.0, scale)
    ]
    return _LaneCertificate(
        low, point^, scale, 0.0, upper, False, cells^, 7, 11
    )


def test_requested_gap_only_tightens_existing_accuracy_across_scales() raises:
    var road = _sampled_road(1.0)
    var ordinary = _scaled_accuracy(road, 0, 0, 0.0, 1.0, 0.5, 1.0, 2.0)
    assert_equal(
        _search_accuracy(road, 0, 0, 0.0, 1.0, 0.5, 1.0, 2.0, None), ordinary
    )
    var gap = ordinary * 0.5
    var expected = min(ordinary, _rebase_lower(gap, 1.0, 2.0))
    assert_equal(
        _search_accuracy(road, 0, 0, 0.0, 1.0, 0.5, 1.0, 2.0, (gap, 1.0)),
        expected,
    )
    assert_true(expected < ordinary)
    assert_equal(
        _search_accuracy(road, 0, 0, 0.0, 1.0, 0.5, 1.0, 2.0, (100.0, 4.0)),
        ordinary,
    )
    var eta = bitcast[DType.float64](UInt64(1))
    assert_equal(
        _search_accuracy(road, 0, 0, 0.0, 1.0, 0.5, 1.0, 2.0, (1.0, eta)), 0.0
    )


def test_zero_gap_resume_preserves_terminal_depths_and_upgrades_only_discrete_domain() raises:
    var road = _sampled_road(1.0)
    var certificate = _three_point_certificate(road)
    var high = _next_up(_next_up(0.5))
    _resume_lane_certificate(
        road, 0, 0, 0.5, high, Vector3(0, 0, 0), certificate, 0.0, 8.0
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, 0.5)
    assert_equal(certificate.scale, 2.0)
    assert_true(certificate.nodes > 7)
    assert_true(certificate.terms > 11)
    assert_true(len(certificate.cells) > 0)
    for cell in certificate.cells:
        assert_equal(cell.low, cell.high)
        assert_true(cell.depth >= 8)
    # The three stored values give an independent finite-domain reference.
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    for s in [Float64(0.5), _next_up(0.5), high]:
        assert_true(
            _wide_point_order(
                certificate.point, road._lane_center(0, 0, s), zero
            )
            <= 0
        )


def test_resuming_an_exact_certificate_does_not_reset_or_spend_work() raises:
    var road = _sampled_road(1.0)
    var high = _next_up(_next_up(0.5))
    var certificate = _three_point_certificate(road)
    _resume_lane_certificate(
        road, 0, 0, 0.5, high, Vector3(0, 0, 0), certificate, 0.0, 8.0
    )
    var nodes = certificate.nodes
    var terms = certificate.terms
    var count = len(certificate.cells)
    _resume_lane_certificate(
        road, 0, 0, 0.5, high, Vector3(0, 0, 0), certificate, 0.0, 2.0
    )
    assert_equal(certificate.nodes, nodes)
    assert_equal(certificate.terms, terms)
    assert_equal(len(certificate.cells), count)
    assert_true(certificate.exact_witness)


def test_failed_resume_preserves_old_cover_and_cumulative_work_on_retry() raises:
    var road = _sampled_road(1.0)
    var high = _next_up(_next_up(0.5))
    var certificate = _three_point_certificate(road)
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            4.0,
            max_terms=11,
        )
    var after_first = certificate.nodes
    assert_true(after_first > 7)
    assert_equal(certificate.terms, 11)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, 0.5)
    assert_equal(certificate.cells[0].high, high)
    assert_equal(certificate.cells[0].depth, 7)
    assert_false(certificate.exact_witness)
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            4.0,
            max_terms=11,
        )
    assert_true(certificate.nodes > after_first)
    assert_equal(certificate.terms, 11)
    var limit = certificate.nodes
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            4.0,
            max_nodes=limit,
        )
    assert_equal(certificate.nodes, limit)
    assert_equal(len(certificate.cells), 1)


def test_resume_does_not_restart_retained_depth_at_zero() raises:
    var road = _sampled_road(1.0)
    var certificate = _three_point_certificate(road)
    with assert_raises(contains="numerical accuracy limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            _next_up(_next_up(0.5)),
            Vector3(0, 0, 0),
            certificate,
            0.0,
            4.0,
            max_depth=7,
        )
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].depth, 7)
    assert_true(certificate.nodes > 7)
    assert_true(certificate.terms > 11)


def test_gap_schedule_retains_previous_request_units_after_scale_change() raises:
    var road = _sampled_road(1.0)
    var certificate = _three_point_certificate(road)
    var first = _next_resume_gap(certificate, 0.5, 2.0)
    assert_true(first > 0.0)
    assert_true(first <= 0.03125)
    certificate.scale = 2.0
    certificate.upper *= 4.0
    var second = _next_resume_gap(certificate, first, 4.0)
    assert_true(second <= first)
    assert_equal(_next_resume_gap(certificate, 0.0, 4.0), 0.0)


def test_resume_rejects_unusable_gap_units_before_changing_state() raises:
    var road = _sampled_road(1.0)
    var certificate = _three_point_certificate(road)
    var high = _next_up(_next_up(0.5))
    for bad in [Float64(-1.0), inf[DType.float64]()]:
        with assert_raises(contains="finite nonnegative gap"):
            _resume_lane_certificate(
                road, 0, 0, 0.5, high, Vector3(0, 0, 0), certificate, bad, 4.0
            )
    for scale in [
        Float64(0.0),
        Float64(-2.0),
        Float64(3.0),
        inf[DType.float64](),
    ]:
        with assert_raises(contains="positive power-of-two scale"):
            _resume_lane_certificate(
                road, 0, 0, 0.5, high, Vector3(0, 0, 0), certificate, 0.0, scale
            )
    assert_equal(certificate.nodes, 7)
    assert_equal(certificate.terms, 11)
    assert_equal(len(certificate.cells), 1)


def test_tolerance_closed_domain_is_not_an_exact_witness() raises:
    var road = _sampled_road(1.0)
    var certificate = _refine_lane_certificate(
        road, 0, 0, 0.0, 1.0, Vector3(0, 0, 0), 0.1, 0.0
    )
    assert_false(certificate.exact_witness)
    var have_interval = False
    for cell in certificate.cells:
        if cell.low < cell.high:
            have_interval = True
    assert_true(have_interval)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
