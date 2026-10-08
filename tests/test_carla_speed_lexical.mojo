# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""OpenDRIVE speed numbers use decimal XML values, without language suffixes."""
from extensions.carla.speed_limits import (
    read_speed_number,
    _speed_decimal_syntax,
)
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_false,
    assert_true,
)


def test_suffix_and_trailing_syntax_are_rejected() raises:
    for text in [
        "0f",
        "0F",
        "0.0f",
        "1f",
        "12f",
        "1.5f",
        "1e2f",
        "0e0f",
        "0ff",
        "0f0",
        "1foo",
        "0abc",
        "0d",
        "0D",
        "0x0",
        "0X0p0",
        "0_0",
        "1_0",
        "0\x00",
        "0 \tx",
        "/",
        ":",
        "é",
    ]:
        with assert_raises(contains="numeric max value"):
            _ = read_speed_number(text)


def test_decimal_exponent_zero_and_negative_zero_are_preserved() raises:
    for text in [
        "0",
        "+0",
        "00",
        "0.",
        ".0",
        "0.0",
        "0e0",
        "0E+1",
        "0e-1",
        " 0.000 \t",
    ]:
        assert_equal(read_speed_number(text), Float64(0))
    assert_equal(read_speed_number("1."), Float64(1))
    assert_equal(read_speed_number(".5"), Float64(0.5))
    assert_equal(read_speed_number("1.e2"), Float64(100))
    assert_equal(read_speed_number("+.5e-2"), Float64(0.005))
    assert_equal(read_speed_number("+1.25e+2"), Float64(125))
    assert_equal(read_speed_number("1.25E-2"), Float64(0.0125))
    assert_equal(
        bitcast[DType.uint64](read_speed_number("-0.0e10")),
        UInt64(0x8000000000000000),
    )


def test_bad_decimal_placement_still_rejects() raises:
    for text in [
        "",
        " ",
        "+",
        "-",
        ".",
        "+.",
        "1..0",
        "1e",
        "1E+",
        "1e-",
        "e1",
        "1e2e3",
        "++0",
        "0-0",
        "0+0",
        "1e+-2",
        "1e2.",
        ".e2",
    ]:
        with assert_raises(contains="numeric max value"):
            _ = read_speed_number(text)


def test_domain_and_underflow_errors_are_preserved() raises:
    for text in ["-1", "-0.1", "1e1000"]:
        with assert_raises(contains="finite and nonnegative"):
            _ = read_speed_number(text)
    for text in ["1e-1000", "-1e-1000", "0.0001e-1000", "+1E-1000"]:
        with assert_raises(contains="underflows Float64"):
            _ = read_speed_number(text)
    assert_equal(read_speed_number("0e-1000"), Float64(0))
    assert_equal(read_speed_number("5e-324"), bitcast[DType.float64](UInt64(1)))


def test_syntax_validator_complete_grammar_boundaries() raises:
    for text in ["0", "+0", "-0", "1.", ".5", "1E2", "1e+2", "1e-2", ".5e2"]:
        assert_true(_speed_decimal_syntax(text))
    for text in [
        "",
        ".",
        "+.",
        "1..0",
        "1e2e3",
        "0-0",
        "0+0",
        "++0",
        "--0",
        "1e",
        "1e+",
        "1e.",
        ".e1",
        "/",
        ":",
        "f",
        "F",
        "nan",
        "INF",
    ]:
        assert_false(_speed_decimal_syntax(text))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
