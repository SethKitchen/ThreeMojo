# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent cycle/easing calculations for the capsule gait, issue #290."""

from extensions.carla.walker_gait import WalkerGait
from std.math import abs, exp, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, SECOND, TURN, Duration, Velocity


def test_cycle_alternates_and_stop_is_continuous() raises:
    var gait = WalkerGait()
    assert_equal(gait.swing().value, 0)
    # 1.5 m/s covers the 1.5 m cycle in one second: a quarter cycle.
    gait.advance(Velocity(1.5), Duration(0.25, SECOND))
    assert_almost_equal(gait.phase().to(TURN), 0.25, atol=1e-6)
    var expected = 18 * (1 - exp(Float64(-0.25 / 0.15)))
    assert_almost_equal(Float64(gait.swing().to(DEGREE)), expected, atol=1e-5)
    gait.advance(Velocity(1.5), Duration(0.5, SECOND))
    assert_almost_equal(gait.phase().to(TURN), 0.75, atol=1e-6)
    assert_true(gait.swing().to(DEGREE) < -17)
    var before = gait.swing().to(DEGREE)
    var phase = gait.phase().value
    gait.advance(Velocity(0), Duration(0, SECOND))
    assert_equal(gait.swing().to(DEGREE), before)
    gait.advance(Velocity(0), Duration(0.015, SECOND))
    assert_equal(gait.phase().value, phase)
    assert_almost_equal(
        Float64(gait.swing().to(DEGREE)),
        Float64(before) * exp(Float64(-0.1)),
        atol=1e-5,
    )
    assert_true(abs(gait.swing().to(DEGREE) - before) < 2)
    gait.advance(Velocity(0), Duration(3, SECOND))
    assert_true(abs(gait.swing().to(DEGREE)) < 1e-6)
    # Restart continues the held phase and grows the amplitude smoothly.
    gait.advance(Velocity(1.5), Duration(0.1, SECOND))
    assert_almost_equal(gait.phase().to(TURN), 0.85, atol=1e-6)
    assert_true(gait.amplitude().to(DEGREE) < 9)


def test_speed_changes_and_partitioned_time() raises:
    var whole = WalkerGait()
    var split = WalkerGait()
    whole.advance(Velocity(1.5), Duration(0.25, SECOND))
    split.advance(Velocity(1.5), Duration(0.1, SECOND))
    split.advance(Velocity(1.5), Duration(0.15, SECOND))
    whole.advance(Velocity(3), Duration(0.25, SECOND))
    split.advance(Velocity(3), Duration(0.05, SECOND))
    split.advance(Velocity(3), Duration(0.2, SECOND))
    # Quarter cycle at 1.5 m/s, then half a cycle at 3 m/s.
    assert_almost_equal(whole.phase().to(TURN), 0.75, atol=1e-6)
    assert_almost_equal(split.phase().value, whole.phase().value, atol=1e-6)
    assert_almost_equal(
        split.amplitude().value, whole.amplitude().value, atol=1e-6
    )
    whole.advance(Velocity(40), Duration(3, SECOND))
    assert_almost_equal(whole.amplitude().to(DEGREE), 30, atol=1e-5)
    # Whole cycles over a long duration retain the existing phase.
    var phase = whole.phase().to(TURN)
    whole.advance(Velocity(1.5), Duration(1000000000, SECOND))
    assert_almost_equal(whole.phase().to(TURN), phase, atol=1e-6)
    assert_true(whole.phase().to(TURN) >= 0 and whole.phase().to(TURN) < 1)


def test_invalid_inputs_are_atomic_and_zero_holds() raises:
    var gait = WalkerGait()
    gait.advance(Velocity(1), Duration(0.1, SECOND))
    var phase = gait.phase().value
    var amplitude = gait.amplitude().value
    for value in [-Float32(1), inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises(contains="speed"):
            gait.advance(Velocity(value), Duration(0.1, SECOND))
        with assert_raises(contains="duration"):
            gait.advance(Velocity(1), Duration(value, SECOND))
        assert_equal(gait.phase().value, phase)
        assert_equal(gait.amplitude().value, amplitude)
    gait.advance(Velocity(40), Duration(0, SECOND))
    assert_equal(gait.phase().value, phase)
    assert_equal(gait.amplitude().value, amplitude)


def test_extreme_finite_distance_remainder() raises:
    # Python Fraction on exact Float32 input values provides these oracles.
    # In particular 2^100 / 1.5 has fractional cycle 2/3, not zero.
    var cases: List[Tuple[Float32, Float32, Float32]] = [
        (
            Float32(1.2676506002282294e30),
            Float32(1.0),
            Float32(0.9166666666666666),
        ),
        (
            Float32(2.535301200456459e30),
            Float32(1.0),
            Float32(0.5833333333333334),
        ),
        (
            Float32(1.2676506002282294e30),
            Float32(1.2676506002282294e30),
            Float32(0.9166666666666666),
        ),
        (
            Float32(1.7014118346046923e38),
            Float32(1.1754943508222875e-38),
            Float32(0.5833333333333334),
        ),
        (
            Float32(3.4028234663852886e38),
            Float32(3.4028234663852886e38),
            Float32(0.25),
        ),
        (
            Float32(1.0000001192092896),
            Float32(1.2676506002282294e30),
            Float32(0.25),
        ),
        (
            Float32(1.1754943508222875e-38),
            Float32(1.7014118346046923e38),
            Float32(0.5833333333333334),
        ),
    ]
    for sample in cases:
        var gait = WalkerGait()
        gait.advance(Velocity(1.5), Duration(0.25, SECOND))
        gait.advance(Velocity(sample[0]), Duration(sample[1], SECOND))
        assert_almost_equal(gait.phase().to(TURN), sample[2], atol=1e-6)


def test_phase_rounding_keeps_the_one_turn_bound() raises:
    var gait = WalkerGait()
    gait.advance(Velocity(1.5), Duration(0.25, SECOND))
    gait.advance(
        Velocity(1.1250001192092896), Duration(0.9999998807907104, SECOND)
    )
    assert_equal(gait.phase().value, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
