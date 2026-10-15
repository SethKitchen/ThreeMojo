# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact helpers of the reference tools give CPython 3.12's answers.

Every expected value here is what CPython 3.12.14 printed for the same
expression.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools._bigint import BigInt, gcd
from tools._fraction import Fraction
from tools._python_float import parse_float, python_repr
from tools._python_random import PythonRandom


def test_big_integers_divide_and_shift_as_python_does() raises:
    var parts = (BigInt(2) ** 200).divmod(BigInt(3) ** 50)
    assert_equal(parts[0].to_string(), "2238393297946874000179418290327143433")
    assert_equal(parts[1].to_string(), "249667313308346329176559")
    # The quotient floors and the remainder takes the divisor's sign.
    var big = BigInt(2) ** 100
    assert_equal(
        ((-big) // BigInt(7)).to_string(), "-181092942889747057356671886483"
    )
    assert_equal(((-big) % BigInt(7)).to_string(), "5")
    assert_equal(
        (big // BigInt(-7)).to_string(), "-181092942889747057356671886483"
    )
    assert_equal((big % BigInt(-7)).to_string(), "-5")
    # A right shift floors too.
    assert_equal(
        (-(BigInt(2) ** 70 + BigInt(1)) >> 3).to_string(),
        "-147573952589676412929",
    )
    assert_equal(
        (-(BigInt(2) ** 70) >> 3).to_string(), "-147573952589676412928"
    )
    assert_equal(
        BigInt.parse("-123456789012345678901234567890").to_string(),
        "-123456789012345678901234567890",
    )
    assert_equal((BigInt(2) ** 100).bit_length(), 101)
    with assert_raises(contains="division by zero"):
        _ = BigInt(1).divmod(BigInt(0))


def test_big_integers_round_to_float_with_ties_to_even() raises:
    assert_equal(
        python_repr((BigInt(2) ** 53 + BigInt(1)).to_float()),
        "9007199254740992.0",
    )
    assert_equal(
        python_repr((BigInt(2) ** 53 + BigInt(3)).to_float()),
        "9007199254740996.0",
    )
    assert_equal(
        python_repr((BigInt(2) ** 1024 - BigInt(2) ** 971).to_float()),
        "1.7976931348623157e+308",
    )


def test_gcd() raises:
    assert_equal(
        gcd(BigInt(2) ** 300, BigInt(6) ** 100).to_string(),
        "1267650600228229401496703205376",
    )
    assert_equal(
        gcd(BigInt(10) ** 40, BigInt(7) ** 30 * BigInt(10) ** 5).to_string(),
        "100000",
    )
    assert_equal(gcd(BigInt(0), BigInt(-9)).to_string(), "9")


def test_fractions_follow_python() raises:
    assert_equal(
        String(Fraction.from_float(0.1)), "3602879701896397/36028797018963968"
    )
    assert_equal(String(Fraction.of(BigInt(7), BigInt(-21))), "-1/3")
    var a = Fraction.of(BigInt(-7), BigInt(3))
    assert_equal((a // Fraction(2)).to_string(), "-2")
    assert_equal(String(a % Fraction(2)), "5/3")
    assert_equal(String(Fraction.of(BigInt(2), BigInt(3)) ** -2), "9/4")
    # Below the smallest subnormal, a tie rounds to zero; above it, up.
    assert_equal(
        python_repr(Fraction.of(BigInt(1), BigInt(2) ** 1075).to_float()), "0.0"
    )
    assert_equal(
        python_repr(Fraction.of(BigInt(3), BigInt(2) ** 1076).to_float()),
        "5e-324",
    )
    assert_equal(
        python_repr(Fraction.of(BigInt(1), BigInt(3)).to_float()),
        "0.3333333333333333",
    )
    with assert_raises(contains="too large"):
        _ = Fraction(BigInt(2) ** 1100).to_float()


def test_the_twister_draws_python_s_values() raises:
    var draws = PythonRandom(626)
    assert_equal(
        draws.randrange(BigInt(0), BigInt(2139095040)).to_string(), "784844921"
    )
    assert_equal(
        draws.randrange(BigInt(0), BigInt(2139095040)).to_string(), "1662691198"
    )
    assert_equal(
        draws.randrange(BigInt(0), BigInt(2139095040)).to_string(), "261557184"
    )
    assert_equal(
        draws.randrange(
            BigInt(1), BigInt.parse("9218868437227405312")
        ).to_string(),
        "185863576828961027",
    )
    assert_equal(draws.getrandbits(70).to_string(), "740342457605908418751")
    assert_equal(python_repr(draws.random()), "0.7669055784119663")
    var zero = PythonRandom(0)
    assert_equal(zero.getrandbits(32).to_string(), "3626764237")
    var wide = PythonRandom(2**40 + 5)
    assert_equal(wide.getrandbits(32).to_string(), "2166296868")


def test_floats_are_read_and_written_as_python_does() raises:
    assert_equal(python_repr(48654528712316664.0), "4.8654528712316664e+16")
    assert_equal(
        python_repr(parse_float("9.197485623048047e+17")),
        "9.197485623048047e+17",
    )
    for text in [
        "5e-324",
        "1e+16",
        "1000000000000000.0",
        "0.0001",
        "1e-05",
        "-0.0",
        "1.5e+300",
        "0.1",
    ]:
        assert_equal(python_repr(parse_float(text)), text)
    assert_equal(python_repr(parse_float("1e400")), "inf")
    assert_equal(python_repr(parse_float("-inf")), "-inf")
    assert_equal(python_repr(parse_float("nan")), "nan")
    assert_equal(python_repr(parse_float("  2.50 ")), "2.5")
    with assert_raises(contains="could not convert"):
        _ = parse_float("one")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
