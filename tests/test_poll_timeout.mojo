# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Poll timeout checks never execute an unbounded native wait."""

from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Duration, MILLISECOND, SECOND
from window.poll_timeout import poll_milliseconds


def test_whole_milliseconds_keep_the_existing_rounding() raises:
    assert_equal(poll_milliseconds(Duration(0, SECOND)), 0)
    assert_equal(poll_milliseconds(Duration(-0.0, SECOND)), 0)
    assert_equal(poll_milliseconds(Duration(0.5, MILLISECOND)), 0)
    assert_equal(poll_milliseconds(Duration(1.75, MILLISECOND)), 1)
    assert_equal(poll_milliseconds(Duration(1, SECOND)), 1000)


def test_negative_fractions_are_refused_before_integer_conversion() raises:
    for value in [Float32(-0.5), Float32(-1e-6), Float32(-1000)]:
        with assert_raises(contains="negative"):
            _ = poll_milliseconds(Duration(value, MILLISECOND))


def test_nonfinite_and_native_overflow_are_refused() raises:
    for value in [
        inf[DType.float32](),
        nan[DType.float32](),
        Float32(3e6),
        Float32(1e30),
    ]:
        with assert_raises(contains="finite"):
            _ = poll_milliseconds(Duration(value, SECOND))
    with assert_raises(contains="negative"):
        _ = poll_milliseconds(Duration(-inf[DType.float32](), SECOND))


def test_large_representable_timeouts_stay_nonnegative() raises:
    var got = poll_milliseconds(Duration(2e6, SECOND))
    assert_true(got > 0)
    assert_true(got <= Int32.MAX)


def test_native_limit_uses_the_original_duration_before_narrowing() raises:
    # These adjacent Float32 seconds straddle Int32.MAX milliseconds.
    assert_equal(poll_milliseconds(Duration(2147483.5, SECOND)), 2147483500)
    with assert_raises(contains="finite"):
        _ = poll_milliseconds(Duration(2147483.75, SECOND))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
