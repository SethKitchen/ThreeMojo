# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bitwise before/after comparisons of the private grouped Y caller change."""
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope as _new,
    _try_spiral_grouped_roundoff_envelope_metered as _new_metered,
)
from tests._reference_grouped_y_refusal import (
    _try_spiral_grouped_roundoff_envelope as _old,
    _try_spiral_grouped_roundoff_envelope_metered as _old_metered,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _compare(geometry: RoadGeometry, d: _Jet, pieces: Int) raises:
    var old = _old(geometry, d, pieces)
    var new = _new(geometry, d, pieces)
    assert_equal(Bool(old), Bool(new))
    if old:
        assert_equal(
            bitcast[DType.uint64](old.value()[0]),
            bitcast[DType.uint64](new.value()[0]),
        )
        assert_equal(
            bitcast[DType.uint64](old.value()[1]),
            bitcast[DType.uint64](new.value()[1]),
        )
    var before_terms = 17
    var after_terms = 17
    var old_paid = _old_metered(geometry, d, pieces, before_terms, 100000)
    var new_paid = _new_metered(geometry, d, pieces, after_terms, 100000)
    assert_equal(before_terms, after_terms)
    assert_equal(Bool(old_paid), Bool(new_paid))
    if old_paid:
        assert_equal(
            bitcast[DType.uint64](old_paid.value()[0]),
            bitcast[DType.uint64](new_paid.value()[0]),
        )
        assert_equal(
            bitcast[DType.uint64](old_paid.value()[1]),
            bitcast[DType.uint64](new_paid.value()[1]),
        )


@no_inline
def _check_exponent(exponent: Int) raises:
    var scale = bitcast[DType.float64](UInt64(exponent + 1023) << UInt64(52))
    for phase_scale in [-0.7, -0.1, 0.0, 0.1, 0.7]:
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, scale * 2.0),
            0.0,
            phase_scale / scale,
        )
        for width in [0.0, 0.1, 0.4]:
            for allowance in [0.0, 0.01, 0.25]:
                var d = _Jet.variable(scale * (1.0 - width), scale)
                d.error = scale * allowance
                for pieces in [1, 2, 4, 8, 16, 64]:
                    # Typed standalone boundary inputs. This does not assert
                    # that the canonical producer selects these counts.
                    _compare(geometry, d, pieces)


def test_distance_exponent_negative_1022() raises:
    _check_exponent(-1022)


def test_distance_exponent_negative_800() raises:
    _check_exponent(-800)


def test_distance_exponent_negative_600() raises:
    _check_exponent(-600)


def test_distance_exponent_negative_520() raises:
    _check_exponent(-520)


def test_distance_exponent_negative_512() raises:
    _check_exponent(-512)


def test_distance_exponent_negative_500() raises:
    _check_exponent(-500)


def test_distance_exponent_negative_100() raises:
    _check_exponent(-100)


def test_distance_exponent_0() raises:
    _check_exponent(0)


def test_distance_exponent_100() raises:
    _check_exponent(100)


def test_distance_exponent_400() raises:
    _check_exponent(400)


def test_distance_exponent_500() raises:
    _check_exponent(500)


def test_distance_exponent_510() raises:
    _check_exponent(510)


def test_distance_exponent_512() raises:
    _check_exponent(512)


def test_distance_exponent_520() raises:
    _check_exponent(520)


def test_distance_exponent_530() raises:
    _check_exponent(530)


def test_distance_exponent_535() raises:
    _check_exponent(535)


def test_distance_exponent_536() raises:
    _check_exponent(536)


def test_distance_exponent_537() raises:
    _check_exponent(537)


def test_distance_exponent_538() raises:
    _check_exponent(538)


def test_distance_exponent_539() raises:
    _check_exponent(539)


def test_distance_exponent_540() raises:
    _check_exponent(540)


def test_distance_exponent_541() raises:
    _check_exponent(541)


def test_distance_exponent_542() raises:
    _check_exponent(542)


def test_distance_exponent_543() raises:
    _check_exponent(543)


def test_distance_exponent_544() raises:
    _check_exponent(544)


def test_distance_exponent_545() raises:
    _check_exponent(545)


def test_distance_exponent_550() raises:
    _check_exponent(550)


def test_distance_exponent_600() raises:
    _check_exponent(600)


def test_distance_exponent_800() raises:
    _check_exponent(800)


def test_distance_exponent_1000() raises:
    _check_exponent(1000)


def test_distance_exponent_1022() raises:
    _check_exponent(1022)


def test_later_world_origin_refusals_are_unchanged() raises:
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    for origin in [-maximum, -10.0, 0.0, 10.0, maximum]:
        for curvature in [-0.001, 0.0, 0.001]:
            var geometry = with_spiral(
                RoadGeometry(SPIRAL, 0.0, origin, origin, 0.0, 20.0),
                0.0,
                curvature,
            )
            _compare(geometry, _Jet.variable(2.125, 2.25), 4)


def test_count_and_budget_refusals_keep_original_debits() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 20.0), 0.0, 0.001
    )
    var d = _Jet.variable(2.125, 2.25)
    for pieces in [0, 1, 4, 64, 65]:
        _compare(geometry, d, pieces)
        for budget in [0, 17, 18, 100000]:
            var old_terms = 17
            var new_terms = 17
            var old = _old_metered(geometry, d, pieces, old_terms, budget)
            var new = _new_metered(geometry, d, pieces, new_terms, budget)
            assert_equal(old_terms, new_terms)
            assert_equal(Bool(old), Bool(new))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
