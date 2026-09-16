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


def elapsed_after_an_hour_at(frames_per_second: Int) raises -> Float32:
    """Run a clock for an hour at a frame rate, asking for the delta every
    frame, and return what it says has elapsed, in seconds."""
    var clock = Clock()
    var start = 7 * SECOND_NS
    clock.start_at(start)
    var frames = 3600 * frames_per_second
    var summed = Float64(0)
    for frame in range(1, frames + 1):
        # Whole nanoseconds, the endpoints exact, the frames as even as
        # integers allow.
        var now = start + (frame * 3600 * SECOND_NS) // frames
        summed += Float64(clock.delta_at(now).to(SECOND))
    # The deltas themselves are sound: summed in Float64 they come to the
    # hour within what their own Float32 rounding allows.
    assert_almost_equal(summed, Float64(3600), atol=Float64(1e-2))
    return clock.elapsed_at(start + 3600 * SECOND_NS).to(SECOND)


def test_the_elapsed_time_does_not_depend_on_the_frame_rate() raises:
    # An hour is an hour whether it was asked about thirty, sixty or a
    # hundred and twenty times a second. three.js sums its deltas in
    # floating point and drifts here; the reading less the start does not.
    assert_equal(elapsed_after_an_hour_at(30), Float32(3600))
    assert_equal(elapsed_after_an_hour_at(60), Float32(3600))
    assert_equal(elapsed_after_an_hour_at(120), Float32(3600))


def test_a_long_run_keeps_its_precision() raises:
    # A tenth of a second after an hour is a tenth of a second: the count
    # is divided in Float64, and only the answer is rounded to Float32.
    var clock = Clock()
    clock.start_at(0)
    _ = clock.delta_at(3600 * SECOND_NS)
    assert_almost_equal(
        clock.delta_at(3600 * SECOND_NS + 100_000_000).to(MILLISECOND),
        Float32(100),
        atol=Float64(1e-3),
    )
    assert_almost_equal(
        clock.elapsed_at(3600 * SECOND_NS + 100_000_000).to(SECOND),
        Float32(3600.1),
        atol=Float64(1e-3),
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
