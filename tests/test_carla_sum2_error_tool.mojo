# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The Sum2 majorant matches the reviewed rational formula."""

from std.ffi import external_call
from std.memory import bitcast
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import tool_mojo
from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._process import run_program
from tools.carla_sum2_error import sum2_error


def _unit() raises -> Fraction:
    """Return 2**-53."""
    return Fraction.of(BigInt(1), BigInt.power_of_two(53))


def _pow2(exponent: Int) raises -> Fraction:
    """Return 2**exponent as a fraction."""
    if exponent >= 0:
        return Fraction(BigInt.power_of_two(exponent))
    return Fraction.of(BigInt(1), BigInt.power_of_two(-exponent))


def _float(bits: UInt64) -> Float64:
    """Return the Float64 with these little-endian bits."""
    return bitcast[DType.float64](bits)


def _two_sum(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    """Return Python's `two_sum` pair."""
    var value = a + b
    var second = value - a
    var first = value - second
    var error = (a - first) + (b - second)
    return (value, error)


def _sum2(values: List[Float64]) -> Float64:
    """Return the streaming Sum2 total."""
    var total = Float64(0)
    var residual = Float64(0)
    for index in range(len(values)):
        var pair = _two_sum(total, values[index])
        total = pair[0]
        residual += pair[1]
    return total + residual


def _abs_diff(actual: Float64, exact: Fraction) raises -> Fraction:
    """Return the absolute gap between a double and an exact sum."""
    return abs(Fraction.from_float(actual) - exact)


def test_the_formula_matches_python_fraction() raises:
    var counts = List[Int]()
    counts.append(2)
    counts.append(5)
    counts.append(320)
    counts.append(1073741824)
    var magnitude = Fraction.of(BigInt(7), BigInt(3))
    var inherited = Fraction.of(BigInt(5), BigInt(13))
    var unit = _unit()
    for index in range(len(counts)):
        var count = counts[index]
        var gamma = Fraction.of(
            BigInt(count - 1),
            BigInt.power_of_two(53) - BigInt(count - 1),
        )
        var expected = inherited + (unit + gamma * gamma.copy()) * magnitude
        assert_true(
            sum2_error(magnitude, inherited, count) == expected, String(count)
        )
    var wide = sum2_error(Fraction(1), Fraction.of(BigInt(1), BigInt(8)), 5)
    var plain = sum2_error(Fraction(1), Fraction(0), 5)
    assert_true(wide > plain)
    var script = (
        "from fractions import Fraction as F\n"
        "U=F(1,2**53)\n"
        "def bound(m,i,c):\n"
        "    m,i=F(m),F(i)\n"
        "    if m==0 or c==1: return str(i)\n"
        "    nu=(c-1)*U\n"
        "    g=nu/(1-nu)\n"
        "    return str(i+(U+g*g)*m)\n"
        "print(bound(F(7,3),F(5,13),2))\n"
        "print(bound(F(7,3),F(5,13),1073741824))\n"
        "print(bound(0,F(3,7),1073741824))\n"
        "print(bound(2**900,F(3,7),1))\n"
    )
    var python = run_program(["python3", "-c", script], 10, merge_errors=False)
    if python.status != 0:
        raise Error(python.errors)
    var lines = python.output.split("\n")
    assert_equal(String(sum2_error(magnitude, inherited, 2)), lines[0])
    assert_equal(String(sum2_error(magnitude, inherited, 1073741824)), lines[1])
    assert_equal(
        String(
            sum2_error(
                Fraction(0), Fraction.of(BigInt(3), BigInt(7)), 1073741824
            )
        ),
        lines[2],
    )
    assert_equal(
        String(sum2_error(_pow2(900), Fraction.of(BigInt(3), BigInt(7)), 1)),
        lines[3],
    )


def test_zero_and_one_term_keep_the_inherited_error() raises:
    var inherited = Fraction.of(BigInt(3), BigInt(7))
    assert_true(sum2_error(Fraction(0), inherited, 1073741824) == inherited)
    assert_true(sum2_error(_pow2(900), inherited, 1) == inherited)
    var negative = _float(UInt64(1) << 63)
    assert_equal(_sum2(_one(negative)), Float64(0))
    assert_equal(_sum2(_one(Float64(0))), Float64(0))


def _one(value: Float64) -> List[Float64]:
    """Return a one-element list."""
    var values = List[Float64]()
    values.append(value)
    return values^


def test_counts_and_majorants_outside_the_range_fail() raises:
    for count in [0, -1, 1073741825]:
        with assert_raises(contains="unsupported Sum2 count"):
            _ = sum2_error(Fraction(1), Fraction(0), count)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = sum2_error(Fraction(-1), Fraction(0), 2)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = sum2_error(_pow2(900) + Fraction(1), Fraction(0), 2)
    with assert_raises(contains="unsupported Sum2 majorant"):
        _ = sum2_error(Fraction(1), Fraction(-1), 2)
    var tiny = _pow2(-1074)
    var inherited = _pow2(-100)
    var magnitudes = List[Fraction]()
    magnitudes.append(Fraction(0))
    magnitudes.append(tiny^)
    magnitudes.append(Fraction(1))
    magnitudes.append(_pow2(900))
    for count in [1, 2, 320, 1073741824]:
        for index in range(len(magnitudes)):
            var magnitude = magnitudes[index].copy()
            var result = sum2_error(magnitude, inherited, count)
            assert_true(result >= inherited)
            var nu = Fraction(count - 1) * _unit()
            assert_true(nu < _pow2(-23))
            var room = Fraction(8) * magnitude / (Fraction(1) - nu)
            assert_true(room < _pow2(904))


def test_float_sums_stay_inside_the_bound() raises:
    var small = _float(0x3CA0000000000000)
    var smaller = _float(0x3950000000000000)
    var values = List[Float64]()
    values.append(Float64(1))
    values.append(small)
    values.append(smaller)
    var exact = Fraction(0)
    var magnitude = Fraction(0)
    for index in range(len(values)):
        var term = Fraction.from_float(values[index])
        exact = exact + term
        magnitude = magnitude + abs(term)
    var gap = _abs_diff(_sum2(values), exact)
    assert_true(gap > Fraction(0))
    assert_true(gap <= sum2_error(magnitude, Fraction(0), len(values)))
    var stored = List[Float64]()
    stored.append(Float64(1))
    stored.append(Float64(-1))
    var ideal = Fraction(1) + _pow2(-40) + Fraction(-1)
    var error = _abs_diff(_sum2(stored), ideal)
    assert_true(error > sum2_error(Fraction(2), Fraction(0), 2))
    assert_true(error <= sum2_error(Fraction(2), _pow2(-40), 2))
    var wide = _float(0x4341C37937E08000)
    var ordinary = wide + Float64(1) - wide
    assert_equal(ordinary, Float64(0))
    var series = List[Float64]()
    series.append(wide)
    series.append(Float64(1))
    series.append(-wide)
    assert_equal(_sum2(series), Float64(1))
    var weight = Fraction(0)
    for index in range(len(series)):
        weight = weight + abs(Fraction.from_float(series[index]))
    var unit = _unit()
    var gamma = Fraction(2) * unit / (Fraction(1) - Fraction(2) * unit)
    var tight = unit + gamma * gamma.copy() * weight
    assert_true(abs(Fraction.from_float(ordinary) - Fraction(1)) > tight)
    assert_true(
        _abs_diff(_sum2(series), Fraction(1))
        <= sum2_error(weight, Fraction(0), len(series))
    )
    var below = external_call["nextafter", Float64](Float64(2), Float64(0))
    var eta = _float(1)
    var normal = _float(0x0010000000000000)
    var huge = _float(0x7810000000000000)
    _check_sequence(_pair(Float64(1), small))
    var triple = List[Float64]()
    triple.append(below)
    triple.append(small)
    triple.append(Float64(-2))
    _check_sequence(triple)
    var subnormal = List[Float64]()
    subnormal.append(normal)
    subnormal.append(eta)
    subnormal.append(-normal)
    _check_sequence(subnormal)
    var high = List[Float64]()
    high.append(huge)
    high.append(Float64(1))
    high.append(-huge)
    _check_sequence(high)
    var tail = List[Float64]()
    tail.append(huge)
    tail.append(-huge)
    tail.append(eta)
    _check_sequence(tail)


def _pair(first: Float64, second: Float64) -> List[Float64]:
    """Return two floats."""
    var values = List[Float64]()
    values.append(first)
    values.append(second)
    return values^


def _check_sequence(values: List[Float64]) raises:
    """Require Sum2 and each two-sum step to honor the exact bound."""
    var exact = Fraction(0)
    var magnitude = Fraction(0)
    for index in range(len(values)):
        var term = Fraction.from_float(values[index])
        exact = exact + term
        magnitude = magnitude + abs(term)
    assert_true(
        _abs_diff(_sum2(values), exact)
        <= sum2_error(magnitude, Fraction(0), len(values))
    )
    var high = Float64(0)
    for index in range(len(values)):
        var pair = _two_sum(high, values[index])
        var total = Fraction.from_float(pair[0]) + Fraction.from_float(pair[1])
        var pieces = Fraction.from_float(high) + Fraction.from_float(
            values[index]
        )
        assert_true(total == pieces)
        high = pair[0]


def test_the_tool_prints_the_python_fraction() raises:
    var directory = mkdtemp(prefix="sum2 error ")
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_sum2_error",
            "7",
            "3",
            "5",
            "13",
            "5",
        ],
        60,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(
        result.output,
        String(
            sum2_error(
                Fraction.of(BigInt(7), BigInt(3)),
                Fraction.of(BigInt(5), BigInt(13)),
                5,
            )
        )
        + "\n",
    )
    assert_false(result.errors.find("Crashpad") >= 0)
    var refused = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_sum2_error",
            "1",
            "1",
            "0",
            "1",
            "0",
        ],
        30,
        merge_errors=False,
    )
    assert_true(refused.status != 0)
    assert_true(refused.errors.find("unsupported Sum2 count") >= 0)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_sum2_error"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
