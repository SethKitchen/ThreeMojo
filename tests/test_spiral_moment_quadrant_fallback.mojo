# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# GENERATED source-only controls; not compiled or run by the oracle author.
# Immutable words come from derive_controls.py, direct exact-rational quadrature.
# Never alter the TestSuite default per-test five-second duration gate.

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _spiral_counts,
    _reference_jet,
)
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, LINE, _GL_NODES
from extensions.carla.curve_trig import _INV_HALF_PI, _PHASE_LIMIT
from extensions.carla.spiral_moment_proof import (
    _SpiralMomentProof,
    _try_build_spiral_moments,
    _try_spiral_moment_expansion,
    _all_spiral_nodes_quadrant_zero,
)
from math.vector3 import Vector3
from std.math import floor, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_true, assert_false, assert_equal


def _f64(word: UInt64) -> Float64:
    return bitcast[DType.float64](word)


def _encloses(bound: _Interval, low: UInt64, high: UInt64) raises:
    assert_true(bound.is_finite())
    assert_true(bound.contains(_f64(low)))
    assert_true(bound.contains(_f64(high)))


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


def _each_original_node_quadrant_zero(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) raises:
    # Independent enumeration of the original rounded operation graph.
    # The proof's constant-time envelope is not reused to establish this fact.
    var nodes = materialize[_GL_NODES]()
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _Jet.constant(Float64(pieces))
    for piece in range(pieces):
        var start = step * _Jet.constant(Float64(piece))
        for i in range(5):
            var t = start + step * _Jet.constant(0.5) * _Jet.constant(
                1.0 + nodes[i]
            )
            var theta = _Jet.constant(geometry.heading) + t * (
                _Jet.constant(geometry.curvature_start)
                + _Jet.constant(0.5) * rate * t
            )
            var phase = theta.rounded_value()
            assert_true(phase.is_finite())
            assert_true(phase.magnitude() <= _PHASE_LIMIT)
            var selection = (
                theta * _Jet.constant(_INV_HALF_PI) + _Jet.constant(0.5)
            ).rounded_value()
            assert_equal(floor(selection.low), 0.0)
            assert_equal(floor(selection.high), 0.0)


def _proof(count: Int) raises -> _SpiralMomentProof:
    var spent = 0
    var found = _try_build_spiral_moments(count, spent, 110 * count)
    if not found:
        raise Error("Expected bounded count payload")
    assert_equal(spent, 110 * count)
    return found.value().copy()


def _geometry() raises -> RoadGeometry:
    var result = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    result.curvature_end = 0.05
    return result^


# Original mistaken eligible fixture retained as a fallback regression.
comptime _EXPECTED_QUADRANTS: Array[Int, 110] = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
]


def test_original_count22_requires_generic_quadrant_fallback() raises:
    var geometry = _geometry()
    geometry.curvature_end = _f64(UInt64(0x3FB999999999999A))
    var station = _f64(UInt64(0x4033000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 22)
    var proof = _proof(counts[0])
    assert_false(_all_spiral_nodes_quadrant_zero(geometry, d, counts[0]))
    var candidate = _try_spiral_moment_expansion(
        proof, geometry, d, counts, Vector3(0, 0, 0)
    )
    if candidate:
        raise Error("Original ineligible count22 site was accepted")
    var original = _reference_jet(geometry, distance, Vector3(0, 0, 0))
    assert_true(isfinite(original[0].error))
    _encloses(
        original[0].value,
        UInt64(0x4031827C570BB170),
        UInt64(0x4031827C570BB171),
    )
    _encloses(
        original[0].first,
        UInt64(0x3FE3D42BA1333926),
        UInt64(0x3FE3D42BA1333927),
    )
    _encloses(
        original[0].second,
        UInt64(0xBFB3169735552F9B),
        UInt64(0xBFB3169735552F9A),
    )
    assert_true(isfinite(original[1].error))
    _encloses(
        original[1].value,
        UInt64(0x405A59130FF39897),
        UInt64(0x405A59130FF39898),
    )
    _encloses(
        original[1].first,
        UInt64(0x3FE91DB97C11C55F),
        UInt64(0x3FE91DB97C11C560),
    )
    _encloses(
        original[1].second,
        UInt64(0x3FAE23C76FE77596),
        UInt64(0x3FAE23C76FE77597),
    )
    var nodes = materialize[_GL_NODES]()
    var expected = materialize[_EXPECTED_QUADRANTS]()
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _Jet.constant(Float64(counts[0]))
    var at = 0
    var quadrant_one_nodes = 0
    for piece in range(counts[0]):
        var start = step * _Jet.constant(Float64(piece))
        for i in range(5):
            var t = start + step * _Jet.constant(0.5) * _Jet.constant(
                1.0 + nodes[i]
            )
            var theta = _Jet.constant(geometry.heading) + t * (
                _Jet.constant(geometry.curvature_start)
                + _Jet.constant(0.5) * rate * t
            )
            var selection = (
                theta * _Jet.constant(_INV_HALF_PI) + _Jet.constant(0.5)
            ).rounded_value()
            assert_equal(floor(selection.low), Float64(expected[at]))
            assert_equal(floor(selection.high), Float64(expected[at]))
            if expected[at] == 1:
                quadrant_one_nodes += 1
            at += 1
    assert_equal(quadrant_one_nodes, 7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
