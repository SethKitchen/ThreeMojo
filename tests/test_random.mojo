# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The same Mulberry32 arithmetic backs core math and Clearwater."""

from extensions.water.random import Mulberry32
from math.random import mulberry32_step
from math.utils import SeededRandom
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, isfinite, isnan, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_core_and_water_streams_agree_across_state_wrap() raises:
    for seed in [0, 7, 42, -1, 0x100000007, 2463401483]:
        var core = SeededRandom(seed)
        var water = Mulberry32(seed)
        for _ in range(1024):
            assert_equal(core.next(), water.next_unit())
            assert_equal(Int(core.state), water.state)


def test_water_keeps_its_mutable_integer_state_contract() raises:
    var water = Mulberry32(0)
    for state in [-1, 0x100000007, 2463401483]:
        water.state = state
        var bits = UInt32(state & 0xFFFFFFFF)
        assert_equal(water.next_unit(), mulberry32_step(bits))
        assert_equal(water.state, Int(bits))


def test_float_intervals_exclude_rounded_upper_endpoints() raises:
    var adjacent = bitcast[DType.float32](UInt32(0x3F800001))
    var rng = SeededRandom(42)
    assert_equal(rng.float_in(1, adjacent), Float32(1))
    # This seed's first exact draw is 4294967275 / 2^32, which rounds to 1.
    rng = SeededRandom(52078625)
    assert_equal(rng.float_in(0, 1), bitcast[DType.float32](UInt32(0x3F7FFFFF)))
    rng = SeededRandom(52078625)
    assert_equal(
        rng.float_in(-2, -1), bitcast[DType.float32](UInt32(0xBF800001))
    )
    rng = SeededRandom(52078625)
    assert_equal(
        rng.float_in(-1, 0), bitcast[DType.float32](UInt32(0x80000001))
    )


def test_finite_float_intervals_cover_adjacent_and_extreme_bounds() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var lows: List[Float32] = [
        0,
        -tiny,
        -2 * tiny,
        tiny,
        1,
        -1.00000011920928955078125,
        -largest,
        -largest,
        0,
        -100,
        2,
    ]
    var highs: List[Float32] = [
        tiny,
        0,
        -tiny,
        2 * tiny,
        1.00000011920928955078125,
        -1,
        largest,
        0,
        largest,
        300,
        3,
    ]
    for at in range(len(lows)):
        for seed in [0, 42, 52078625, -1]:
            var rng = SeededRandom(seed)
            var control = SeededRandom(seed)
            for _ in range(256):
                var value = rng.float_in(lows[at], highs[at])
                _ = control.next()
                assert_true(isfinite(value))
                assert_true(value >= lows[at])
                assert_true(value < highs[at])
                assert_equal(rng.state, control.state)


def test_equal_bounds_keep_value_and_advance_once() raises:
    var rng = SeededRandom(42)
    var control = SeededRandom(42)
    for value in [Float32(3), Float32(-5), Float32(0), Float32(-0.0)]:
        assert_equal(
            bitcast[DType.uint32](rng.float_in(value, value)),
            bitcast[DType.uint32](value),
        )
        _ = control.next()
        assert_equal(rng.state, control.state)


def test_ordinary_float_arithmetic_and_integer_sequence_are_unchanged() raises:
    var rng = SeededRandom(42)
    var control = SeededRandom(42)
    for _ in range(256):
        var expected = Float32(2) + Float32(control.next()) * Float32(5)
        assert_equal(rng.float_in(2, 7), expected)
    assert_equal(rng.int_in(1, 100), control.int_in(1, 100))


def test_other_bounds_keep_previous_ieee_arithmetic() raises:
    var lows: List[Float32] = [
        5,
        -inf[DType.float32](),
        0,
        nan[DType.float32](),
        0,
    ]
    var highs: List[Float32] = [
        -2,
        1,
        inf[DType.float32](),
        1,
        nan[DType.float32](),
    ]
    for at in range(len(lows)):
        var rng = SeededRandom(42)
        var control = SeededRandom(42)
        var expected = lows[at] + Float32(control.next()) * (
            highs[at] - lows[at]
        )
        var value = rng.float_in(lows[at], highs[at])
        if isnan(expected):
            assert_true(isnan(value))
        else:
            assert_equal(value, expected)
        assert_equal(rng.state, control.state)


def test_random_vectors_keep_half_open_components_and_draw_order() raises:
    var rng = SeededRandom(52078625)
    var control = SeededRandom(52078625)
    var pair = Vector2.random(rng)
    assert_equal(pair.x, control.float_in(0, 1))
    assert_equal(pair.y, control.float_in(0, 1))
    assert_true(pair.x < 1)
    assert_equal(rng.state, control.state)
    rng = SeededRandom(52078625)
    control = SeededRandom(52078625)
    var triple = Vector3.random(rng)
    assert_equal(triple.x, control.float_in(0, 1))
    assert_equal(triple.y, control.float_in(0, 1))
    assert_equal(triple.z, control.float_in(0, 1))
    assert_true(triple.x < 1)
    assert_equal(rng.state, control.state)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
