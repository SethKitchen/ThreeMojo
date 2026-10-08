# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Typed malformed payloads exercise explicit private-boundary validation.

These are rejection controls, not claims that canonical producers emit reversed
or nonfinite intervals. No unsafe memory access or fabricated trace is used.
"""
from extensions.carla.curve_interval import _Interval
from extensions.carla.spiral_domain_proof import (
    _try_pack_spiral_proof,
    _spiral_proof_matches,
)
from extensions.carla.spiral_roundoff_proof import _try_spiral_roundoff_envelope
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import _geometry, _road, _capture, _proof
from tests.test_carla_junction_arithmetic_states import _valid


def test_pack_rejects_nonfinite_raw_payload_after_finite_rounded_domain() raises:
    var road = _road(_geometry())
    _valid(road)
    var original = _capture(road, 2.125, 2.25)
    for malformed in [False, True]:
        var captured = original
        if malformed:
            captured.d.value = _Interval(
                inf[DType.float64](), -inf[DType.float64]()
            )
            captured.d.error = 1.0
            assert_false(captured.d.value.is_finite())
            assert_true(captured.d.rounded_value().is_finite())
            assert_true(
                captured.d.rounded_value().low > captured.d.rounded_value().high
            )
        var terms = 17
        var units = 9
        var result = _try_pack_spiral_proof(
            road, 2.125, 2.25, 0, captured, 0, terms, units
        )
        assert_equal(Bool(result), not malformed)
        # Validation consumed the same complete optional reservation.
        assert_equal(terms, 161)
        assert_equal(units, 153)


def test_match_rejects_malformed_raw_jet_against_valid_proof() raises:
    var road = _road(_geometry())
    _valid(road)
    var capture = _capture(road, 2.125, 2.25)
    var proof = _proof(road, 2.125, 2.25)
    for malformed in [False, True]:
        var d = capture.d
        if malformed:
            d.value = _Interval(inf[DType.float64](), -inf[DType.float64]())
            d.error = 1.0
            assert_true(d.rounded_value().is_finite())
        assert_equal(
            _spiral_proof_matches(
                proof,
                road.info.geometries[0].geometry,
                0,
                2.125,
                2.25,
                2.125,
                2.25,
                d,
                (capture.first_count, capture.last_count),
            ),
            not malformed,
        )


def test_roundoff_refuses_nonfinite_raw_value_and_error_independently() raises:
    var road = _road(_geometry())
    _valid(road)
    var capture = _capture(road, 2.125, 2.25)
    assert_equal(capture.first_count, capture.last_count)
    for fault in range(3):
        var d = capture.d
        if fault == 1:
            d.value = _Interval(inf[DType.float64](), -inf[DType.float64]())
            d.error = 1.0
        elif fault == 2:
            d.error = -inf[DType.float64]()
        assert_true(d.rounded_value().is_finite())
        assert_equal(
            Bool(
                _try_spiral_roundoff_envelope(
                    road.info.geometries[0].geometry, d, capture.first_count
                )
            ),
            fault == 0,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
