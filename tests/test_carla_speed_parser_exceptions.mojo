# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Fresh source control for the maintained SDK's real converter exception.

The decimal grammar admits the long token. The installed Float64 converter
must independently raise, and read_speed_number must translate that actual
exception. No injected parser or synthetic coverage trace is used.
"""

from extensions.carla.speed_limits import (
    _speed_decimal_syntax,
    read_speed_number,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_valid_decimal_converter_exception_is_translated() raises:
    var number = String("123456789012345678901234567890")
    assert_equal(number.byte_length(), 30)
    assert_true(_speed_decimal_syntax(number))
    # Assert the underlying cause separately, so lexical/range rejection
    # cannot masquerade as execution of the converter exception handler.
    with assert_raises(contains="too long"):
        _ = Float64(number)
    with assert_raises(contains="OpenDRIVE speed needs a numeric max value"):
        _ = read_speed_number(number)


def test_short_decimal_and_range_neighbors_remain_distinct() raises:
    for number in [String("1000000000000000000"), "1e18"]:
        assert_true(_speed_decimal_syntax(number))
        assert_equal(read_speed_number(number), Float64(1e18))
    assert_equal(read_speed_number(" 1.25e1 "), Float64(12.5))
    assert_equal(read_speed_number("0e-1000"), Float64(0.0))
    with assert_raises(contains="finite and nonnegative"):
        _ = read_speed_number("1e1000")
    with assert_raises(contains="underflows Float64"):
        _ = read_speed_number("1e-1000")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
