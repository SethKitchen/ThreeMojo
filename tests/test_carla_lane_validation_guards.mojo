# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Mutable certificate and owner-domain refusal controls for lane search."""

from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _LaneCertificate,
    _continue_lane_certificate,
    _refine_lane_certificate,
    _resume_lane_certificate,
)
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def _certificate(road: Road) raises -> _LaneCertificate:
    return _whole_certificate(road, Vector3(0.5, 0, 0), 0.0, 1.0, 0.5)


def _continue(road: Road, mut certificate: _LaneCertificate) raises:
    _continue_lane_certificate(
        road, 0, 0, 0.0, 1.0, Vector3(0.5, 0, 0), certificate, None, 1.0
    )


def test_valid_owner_and_nonexact_cover_can_resume_to_zero_distance() raises:
    var road = _road()
    var certificate = _certificate(road)
    _continue(road, certificate)
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, 0.5)
    assert_equal(certificate.point[0], 0.5)
    assert_equal(certificate.point[1], 0.0)
    assert_equal(certificate.point[2], 0.0)
    assert_true(len(certificate.cells) > 0)


def test_refinement_rejects_each_nonfinite_scalar_before_work() raises:
    var road = _road()
    var infinity = inf[DType.float64]()
    for values in [
        (-infinity, Float64(1.0), Float64(0.5)),
        (Float64(0.0), infinity, Float64(0.5)),
        (Float64(0.0), Float64(1.0), infinity),
    ]:
        with assert_raises(contains="finite parameter bounds"):
            _ = _refine_lane_certificate(
                road,
                0,
                0,
                values[0],
                values[1],
                Vector3(0, 0, 0),
                values[2],
                0.0,
            )
    for values in [
        (Float64(1.0), Float64(0.0), Float64(0.5)),
        (Float64(0.0), Float64(1.0), Float64(-0.5)),
        (Float64(0.0), Float64(1.0), Float64(1.5)),
    ]:
        with assert_raises(contains="seed is outside"):
            _ = _refine_lane_certificate(
                road,
                0,
                0,
                values[0],
                values[1],
                Vector3(0, 0, 0),
                values[2],
                0.0,
            )


def test_both_resumption_entries_refuse_invalid_owner_bounds() raises:
    var road = _road()
    var infinity = inf[DType.float64]()
    for values in [
        (-infinity, Float64(1.0)),
        (Float64(0.0), infinity),
        (Float64(1.0), Float64(0.0)),
    ]:
        for wrapper in [False, True]:
            var certificate = _certificate(road)
            var terms = certificate.terms
            with assert_raises(contains="finite ordered parameter bounds"):
                if wrapper:
                    _resume_lane_certificate(
                        road,
                        0,
                        0,
                        values[0],
                        values[1],
                        Vector3(0.5, 0, 0),
                        certificate,
                        0.0,
                        1.0,
                    )
                else:
                    _continue_lane_certificate(
                        road,
                        0,
                        0,
                        values[0],
                        values[1],
                        Vector3(0.5, 0, 0),
                        certificate,
                        None,
                        1.0,
                    )
            assert_equal(certificate.nodes, 0)
            assert_equal(certificate.terms, terms)


def test_internal_resumption_rejects_invalid_requested_gap() raises:
    var road = _road()
    for gap in [inf[DType.float64](), Float64(-1.0)]:
        var certificate = _certificate(road)
        var terms = certificate.terms
        with assert_raises(contains="finite nonnegative gap"):
            _continue_lane_certificate(
                road, 0, 0, 0.0, 1.0, Vector3(0.5, 0, 0), certificate, gap, 1.0
            )
        assert_equal(certificate.nodes, 0)
        assert_equal(certificate.terms, terms)


def test_resumption_rejects_nonfinite_and_outside_incumbents() raises:
    var road = _road()
    for station in [inf[DType.float64](), Float64(-0.5), Float64(1.5)]:
        var certificate = _certificate(road)
        certificate.s = station
        var terms = certificate.terms
        with assert_raises(contains="incumbent is outside"):
            _continue(road, certificate)
        assert_equal(certificate.nodes, 0)
        assert_equal(certificate.terms, terms)


def test_negative_consumed_work_is_rejected_without_resetting_ledger() raises:
    var road = _road()
    for node_field in [False, True]:
        var certificate = _certificate(road)
        if node_field:
            certificate.nodes = -1
        else:
            certificate.terms = -1
        var nodes = certificate.nodes
        var terms = certificate.terms
        with assert_raises(contains="nonnegative consumed work"):
            _continue(road, certificate)
        assert_equal(certificate.nodes, nodes)
        assert_equal(certificate.terms, terms)


def test_empty_nonexact_cover_cannot_resume() raises:
    var road = _road()
    var certificate = _certificate(road)
    certificate.cells.clear()
    with assert_raises(contains="possible minimizing cells"):
        _continue(road, certificate)


def test_every_invalid_cell_endpoint_is_rejected_independently() raises:
    var road = _road()
    var infinity = inf[DType.float64]()
    for values in [
        (-infinity, Float64(1.0)),
        (Float64(0.0), infinity),
        (Float64(-0.25), Float64(1.0)),
        (Float64(0.0), Float64(1.25)),
        (Float64(0.75), Float64(0.25)),
    ]:
        var certificate = _certificate(road)
        certificate.cells[0] = _ClosedInterval(
            values[0], values[1], 0, 0.0, 1.0
        )
        var terms = certificate.terms
        with assert_raises(contains="cell is outside its original interval"):
            _continue(road, certificate)
        assert_equal(certificate.nodes, 0)
        assert_equal(certificate.terms, terms)


def test_negative_cell_depth_cannot_become_a_fresh_search_budget() raises:
    var road = _road()
    var certificate = _certificate(road)
    certificate.cells[0].depth = -1
    with assert_raises(contains="nonnegative cell depth"):
        _continue(road, certificate)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
