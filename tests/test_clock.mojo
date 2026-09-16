# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.clock`.

The arithmetic is tested at given counter readings, so nothing waits; the
real counter is read once, to see that the public methods reach it.
"""

from core.clock import Clock
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import MILLISECOND, SECOND

comptime TOLERANCE = Float64(1e-6)

# One second, in the counter's nanoseconds.
comptime SECOND_NS = 1_000_000_000


def test_a_clock_starts_itself_on_the_first_question() raises:
    var clock = Clock()
    assert_false(clock.running)
    # The first delta starts it and is zero: there is nothing to measure from.
    assert_equal(clock.delta_at(5 * SECOND_NS).value, Float32(0))
    assert_true(clock.running)
    assert_almost_equal(
        clock.delta_at(5 * SECOND_NS + SECOND_NS // 2).to(SECOND),
        Float32(0.5),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        clock.elapsed_at(7 * SECOND_NS).to(SECOND), Float32(2), atol=TOLERANCE
    )


def test_deltas_add_up_to_the_elapsed_time() raises:
    var clock = Clock()
    clock.start_at(SECOND_NS)
    var total = Float32(0)
    for step in range(1, 5):
        total += clock.delta_at(SECOND_NS + step * 250_000_000).to(SECOND)
    assert_almost_equal(total, Float32(1), atol=TOLERANCE)
    assert_almost_equal(
        clock.elapsed_at(2 * SECOND_NS).to(SECOND), Float32(1), atol=TOLERANCE
    )
    # Elapsed brings the clock up to date, so the next delta is measured
    # from the elapsed question, not the one before it.
    assert_almost_equal(
        clock.delta_at(2 * SECOND_NS + 100_000_000).to(MILLISECOND),
        Float32(100),
        atol=Float64(1e-3),
    )


def test_a_stopped_clock_keeps_its_time_and_measures_nothing() raises:
    var clock = Clock()
    clock.start_at(0)
    clock.stop_at(3 * SECOND_NS)
    assert_false(clock.running)
    assert_almost_equal(
        clock.elapsed_at(9 * SECOND_NS).to(SECOND), Float32(3), atol=TOLERANCE
    )
    assert_equal(clock.delta_at(10 * SECOND_NS).value, Float32(0))
    # Stopping also turns off starting on the next question.
    assert_false(clock.auto_start)
    assert_false(clock.running)
    # Only start sets it going again, from nothing.
    clock.start_at(20 * SECOND_NS)
    assert_almost_equal(
        clock.elapsed_at(21 * SECOND_NS).to(SECOND), Float32(1), atol=TOLERANCE
    )


def test_a_clock_told_not_to_start_itself_waits_for_start() raises:
    var clock = Clock(auto_start=False)
    assert_equal(clock.delta_at(SECOND_NS).value, Float32(0))
    assert_equal(clock.elapsed_at(2 * SECOND_NS).value, Float32(0))
    assert_false(clock.running)
    clock.start_at(2 * SECOND_NS)
    assert_almost_equal(
        clock.elapsed_at(3 * SECOND_NS).to(SECOND), Float32(1), atol=TOLERANCE
    )


def test_the_public_methods_read_the_real_counter() raises:
    # No waiting: only that time does not run backwards.
    var clock = Clock()
    clock.start()
    assert_true(clock.running)
    assert_true(clock.delta().value >= 0)
    assert_true(clock.elapsed().value >= 0)
    clock.stop()
    assert_false(clock.running)
    assert_equal(clock.delta().value, Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
