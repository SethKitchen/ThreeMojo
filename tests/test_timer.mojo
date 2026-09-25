# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.timer`.

The expected numbers come from three.js 0.180's `Timer`, run in Node with
the same timestamps. The arithmetic is tested at given counter readings,
so nothing waits.
"""

from core.timer import Timer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND

comptime TOLERANCE = Float64(1e-6)

# One millisecond, in the counter's nanoseconds.
comptime MS = 1_000_000


def test_updates_match_three_js() raises:
    # three.js: a start of 1000 ms, then updates at 1016, 1041 and 1049,
    # the last two at time scales of 2 and -0.5.
    var timer = Timer(start=1000 * MS)
    assert_equal(timer.delta().to(SECOND), Float32(0))
    timer.update_at(1016 * MS)
    assert_almost_equal(
        timer.delta().to(SECOND), Float32(0.016), atol=TOLERANCE
    )
    assert_almost_equal(
        timer.elapsed().to(SECOND), Float32(0.016), atol=TOLERANCE
    )
    timer.set_timescale(2)
    timer.update_at(1041 * MS)
    assert_almost_equal(timer.delta().to(SECOND), Float32(0.05), atol=TOLERANCE)
    assert_almost_equal(
        timer.elapsed().to(SECOND), Float32(0.066), atol=TOLERANCE
    )
    timer.set_timescale(-0.5)
    timer.update_at(1049 * MS)
    assert_almost_equal(
        timer.delta().to(SECOND), Float32(-0.004), atol=TOLERANCE
    )
    assert_almost_equal(
        timer.elapsed().to(SECOND), Float32(0.062), atol=TOLERANCE
    )
    # Asking again changes nothing.
    assert_almost_equal(
        timer.delta().to(SECOND), Float32(-0.004), atol=TOLERANCE
    )


def test_a_timescale_that_is_not_finite_is_refused() raises:
    var timer = Timer(start=0)
    with assert_raises():
        timer.set_timescale(inf[DType.float64]())
    with assert_raises():
        timer.set_timescale(nan[DType.float64]())
    assert_equal(timer.timescale, 1)


def test_reset_measures_the_next_delta_from_now() raises:
    var timer = Timer(start=0)
    timer.update_at(10 * MS)
    timer.reset_at(90 * MS)
    timer.update_at(100 * MS)
    assert_almost_equal(timer.delta().to(SECOND), Float32(0.01), atol=TOLERANCE)
    assert_almost_equal(
        timer.elapsed().to(SECOND), Float32(0.02), atol=TOLERANCE
    )


def test_a_hidden_page_stops_the_timer_and_showing_it_resets() raises:
    var timer = Timer(start=0)
    timer.update_at(10 * MS)
    timer.set_hidden_at(True, 20 * MS)
    assert_true(timer.hidden)
    timer.update_at(500 * MS)
    assert_equal(timer.delta().to(SECOND), Float32(0))
    timer.set_hidden_at(False, 1000 * MS)
    assert_false(timer.hidden)
    timer.update_at(1016 * MS)
    assert_almost_equal(
        timer.delta().to(SECOND), Float32(0.016), atol=TOLERANCE
    )
    assert_almost_equal(
        timer.elapsed().to(SECOND), Float32(0.026), atol=TOLERANCE
    )


def test_the_public_methods_read_the_counter() raises:
    var timer = Timer()
    timer.update()
    assert_true(timer.delta().to(SECOND) >= 0)
    timer.reset()
    timer.set_hidden(True)
    timer.update()
    assert_equal(timer.delta().to(SECOND), Float32(0))
    timer.set_hidden(False)
    timer.update()
    assert_true(timer.elapsed().to(SECOND) >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
