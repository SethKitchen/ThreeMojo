# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The SPIRAL moment table falls back to the generic evaluator on a miss,
and each of its words lies inside the interval the builder computes."""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _spiral_counts,
    _reference_jet,
)
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.spiral_moment_proof import _try_build_spiral_moments
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof,
    _try_lookup_spiral_moments,
    _try_spiral_moment_expansion,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_true, assert_false, assert_equal


def _same_interval(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(
        bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high)
    )


def _same_jet(one: _Jet, two: _Jet) raises:
    _same_interval(one.value, two.value)
    _same_interval(one.first, two.first)
    _same_interval(one.second, two.second)
    assert_equal(
        bitcast[DType.uint64](one.error), bitcast[DType.uint64](two.error)
    )


def _compare_builder(count: Int) raises:
    var dynamic_spent = 0
    var dynamic = _try_build_spiral_moments(count, dynamic_spent, 110 * count)
    if not dynamic:
        raise Error("Dynamic control proof unavailable")
    assert_equal(dynamic_spent, 110 * count)
    var table_spent = 0
    var table = _try_lookup_spiral_moments(count, table_spent, 22)
    if not table:
        raise Error("Table control proof unavailable")
    assert_equal(table_spent, 22)
    assert_equal(table.value().pieces, count)
    for index in range(11):
        var cosine = table.value().coefficient(False, index)
        var sine = table.value().coefficient(True, index)
        assert_true(cosine.is_finite())
        assert_true(sine.is_finite())
        assert_true(dynamic.value().cosine[index].contains(cosine.low))
        assert_true(dynamic.value().cosine[index].contains(cosine.high))
        assert_true(dynamic.value().sine[index].contains(sine.low))
        assert_true(dynamic.value().sine[index].contains(sine.high))


def _table_or_generic(
    geometry: RoadGeometry, distance: _Jet, available: Bool
) -> Tuple[_Jet, _Jet, _Jet]:
    # Test-only caller: the miss path is exactly the original evaluator.
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    var spent = 0
    var proof = _try_lookup_spiral_moments(counts[0], spent, 22, available)
    if proof:
        var candidate = _try_spiral_moment_expansion(
            proof.value(), geometry, d, counts, Vector3(0, 0, 0)
        )
        if candidate:
            return candidate.value()
    return _reference_jet(geometry, distance, Vector3(0, 0, 0))


def _assert_generic_fallback(
    geometry: RoadGeometry, distance: _Jet, available: Bool
) raises:
    var actual = _table_or_generic(geometry, distance, available)
    var expected = _reference_jet(geometry, distance, Vector3(0, 0, 0))
    _same_jet(actual[0], expected[0])
    _same_jet(actual[1], expected[1])
    _same_jet(actual[2], expected[2])


def test_missing_table_preserves_budget_and_generic_fallback() raises:
    var spent = 17
    var missing = _try_lookup_spiral_moments(4, spent, 1000, False)
    if missing:
        raise Error("Disabled table returned a view")
    assert_equal(spent, 17)
    var geometry = RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_end = 0.05
    _assert_generic_fallback(geometry, _Jet.variable(2.125, 2.125), False)


def test_table_invalid_accessor_never_indexes_storage() raises:
    var invalid: List[Int] = [-1, 0, 65]
    for count in invalid:
        var proof = _SpiralMomentProof(count)
        assert_false(proof.coefficient(False, 0).is_finite())
        assert_false(proof.coefficient(True, 10).is_finite())
    var boundaries: List[Int] = [1, 64]
    for count in boundaries:
        var proof = _SpiralMomentProof(count)
        assert_false(proof.coefficient(False, -1).is_finite())
        assert_false(proof.coefficient(True, 11).is_finite())
        assert_true(proof.coefficient(False, 0).is_finite())
        assert_true(proof.coefficient(True, 10).is_finite())


def test_count64_hit_count65_miss_preserves_generic() raises:
    var geometry = RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 100.0, 0.0, 128.0)
    geometry.curvature_end = 0.0
    var d = _geometry_distance(geometry, _Jet.variable(62.5, 62.5))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 64)
    assert_equal(counts[1], 64)
    var spent = 0
    var proof = _try_lookup_spiral_moments(64, spent, 22)
    if not proof:
        raise Error("Count64 boundary unavailable")
    var accepted = _try_spiral_moment_expansion(
        proof.value(), geometry, d, counts, Vector3(0, 0, 0)
    )
    if not accepted:
        raise Error("Eligible count64 boundary rejected")
    assert_equal(accepted.value()[0].error, inf[DType.float64]())
    assert_equal(accepted.value()[1].error, inf[DType.float64]())
    var unsupported = _Jet.variable(63.5, 63.5)
    var count65 = _spiral_counts(
        geometry, _geometry_distance(geometry, unsupported)
    )
    assert_equal(count65[0], 65)
    assert_equal(count65[1], 65)
    _assert_generic_fallback(geometry, unsupported, True)


def test_count_clamp_quadrant_misses_preserve_generic() raises:
    var geometry = RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_end = 0.0
    _assert_generic_fallback(geometry, _Jet.variable(0.99, 1.01), True)
    _assert_generic_fallback(geometry, _Jet.variable(0.0, 0.0), True)
    _assert_generic_fallback(geometry, _Jet.variable(20.0, 20.0), True)
    geometry.curvature_end = 0.1
    _assert_generic_fallback(geometry, _Jet.variable(19.0, 19.0), True)


def test_every_table_word_lies_in_the_built_enclosure() raises:
    for count in range(1, 65):
        _compare_builder(count)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
