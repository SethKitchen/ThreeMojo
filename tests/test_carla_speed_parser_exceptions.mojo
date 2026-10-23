# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Fresh source control for the speed number converter.

The decimal grammar admits a token of any length. The installed Float64
converter reads that token and rounds it. It has no failure for a text that
the grammar admits, so `read_speed_number` has no parse-failure line.
"""

from extensions.carla.speed_limits import (
    _speed_decimal_syntax,
    read_speed_number,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_a_long_decimal_is_read_and_rounded() raises:
    var number = String("123456789012345678901234567890")
    assert_equal(number.byte_length(), 30)
    assert_true(_speed_decimal_syntax(number))
    assert_equal(Float64(number), Float64(1.2345678901234568e29))
    assert_equal(read_speed_number(number), Float64(1.2345678901234568e29))


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
