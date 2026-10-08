# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Distance representation is validated without changing canonical proofs."""
from extensions.carla.curve_bounds import _lane_jet, _lane_jet_with_proof
from extensions.carla.curve_interval import _Interval
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _try_pack_spiral_proof,
    _spiral_proof_matches,
)
from tests._reference_spiral_domain_validation import (
    _try_pack_spiral_proof as _old_pack,
    _spiral_proof_matches as _old_match,
)
from tests._spiral_domain_controls import (
    _geometry,
    _road,
    _capture,
    _proof,
    _point_bits,
)
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false


def _same_proof(one: _SpiralDomainProof, two: _SpiralDomainProof) raises:
    assert_equal(one.segment_index, two.segment_index)
    assert_equal(one.record_at, two.record_at)
    assert_equal(one.first_count, two.first_count)
    assert_equal(one.last_count, two.last_count)
    for pair in [
        (one.rounded_d.low, two.rounded_d.low),
        (one.rounded_d.high, two.rounded_d.high),
        (one.first_x_error, two.first_x_error),
        (one.first_y_error, two.first_y_error),
        (one.last_x_error, two.last_x_error),
        (one.last_y_error, two.last_y_error),
    ]:
        assert_equal(
            bitcast[DType.uint64](pair[0]), bitcast[DType.uint64](pair[1])
        )


def _malformed(
    var captured: _SpiralRootCapture, fault: Int
) -> _SpiralRootCapture:
    if fault == 1:
        captured.d.error = -1e-10
    elif fault == 2:
        captured.d.error = -0.01
    elif fault == 3:
        captured.d.error = -0.1
    elif fault == 4:
        captured.d.error = inf[DType.float64]()
    elif fault == 5:
        captured.d.error = -inf[DType.float64]()
    elif fault == 6:
        captured.d.error = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    elif fault == 7:
        captured.d.value = _Interval(2.25, 2.125)
        captured.d.error = 0.0
    elif fault == 8:
        captured.d.value = _Interval(
            inf[DType.float64](), -inf[DType.float64]()
        )
        captured.d.error = 1.0
    elif fault == 9:
        captured.d.value = _Interval.whole()
    elif fault == 10:
        captured.d.first = _Interval.whole()
    elif fault == 11:
        captured.d.second = _Interval.whole()
    elif fault == 12:
        captured.d.error = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    elif fault == 13:
        captured.d.value = _Interval(
            bitcast[DType.float64](UInt64(0x7FF8000000000001)), 2.25
        )
    elif fault == 14:
        captured.d.value = _Interval(2.25, 2.125)
        captured.d.error = 0.1
    return captured


def test_canonical_fields_debits_and_consumers_match_predecessor() raises:
    var road = _road(_geometry())
    for low in [2.125, 1.5]:
        var captured = _capture(road, low, 2.25)
        var old_terms = 17
        var old_units = 9
        var terms = 17
        var units = 9
        var old = _old_pack(
            road, low, 2.25, 0, captured, 0, old_terms, old_units
        ).value()
        var result = _try_pack_spiral_proof(
            road, low, 2.25, 0, captured, 0, terms, units
        ).value()
        _same_proof(old, result)
        assert_equal(terms, old_terms)
        assert_equal(units, old_units)
        _point_bits(
            _lane_jet_with_proof(road, 0, 0, low, 2.25, low, 2.25, old),
            _lane_jet_with_proof(road, 0, 0, low, 2.25, low, 2.25, result),
        )


def test_malformed_categories_refuse_after_the_same_reservation() raises:
    var road = _road(_geometry())
    var original = _capture(road, 2.125, 2.25)
    var proof = _proof(road, 2.125, 2.25)
    for fault in range(1, 15):
        var changed = _malformed(original, fault)
        var old_terms = 17
        var old_units = 9
        var terms = 17
        var units = 9
        var old = _old_pack(
            road, 2.125, 2.25, 0, changed, 0, old_terms, old_units
        )
        var result = _try_pack_spiral_proof(
            road, 2.125, 2.25, 0, changed, 0, terms, units
        )
        print("DISTANCE_REPRESENTATION", fault, Bool(old), Bool(result))
        assert_equal(Bool(old), fault <= 3 or fault == 7 or fault == 14)
        assert_false(Bool(result))
        assert_equal(terms, 161)
        assert_equal(units, 153)
        assert_equal(terms, old_terms)
        assert_equal(units, old_units)
        var counts = (original.first_count, original.last_count)
        assert_equal(
            _old_match(
                proof,
                road.info.geometries[0].geometry,
                0,
                2.125,
                2.25,
                2.125,
                2.25,
                changed.d,
                counts,
            ),
            fault <= 3 or fault == 5 or fault == 7 or fault == 14,
        )
        assert_false(
            _spiral_proof_matches(
                proof,
                road.info.geometries[0].geometry,
                0,
                2.125,
                2.25,
                2.125,
                2.25,
                changed.d,
                counts,
            )
        )


def test_old_malformed_successes_still_fall_back_conservatively() raises:
    var road = _road(_geometry())
    var original = _capture(road, 2.125, 2.25)
    var generic = _lane_jet(road, 0, 0, 2.125, 2.25)
    for fault in [1, 2, 3, 7, 14]:
        var changed = _malformed(original, fault)
        var terms = 17
        var units = 9
        var old = _old_pack(
            road, 2.125, 2.25, 0, changed, 0, terms, units
        ).value()
        assert_false(
            _spiral_proof_matches(
                old,
                road.info.geometries[0].geometry,
                0,
                2.125,
                2.25,
                2.125,
                2.25,
                original.d,
                (original.first_count, original.last_count),
            )
        )
        _point_bits(
            _lane_jet_with_proof(road, 0, 0, 2.125, 2.25, 2.125, 2.25, old),
            generic,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
