# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact remainder controls in assets/math_remainder/ are current.

The generator rebuilds both fixtures from exact fractions and compares them
with the saved files.
"""

from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools.reference_remainders import exact, pairs, rounded, run


def test_the_saved_fixtures_match_the_exact_oracle() raises:
    var outcome = run(".", False)
    assert_equal(outcome[0], 0, outcome[1])
    assert_equal(
        outcome[1],
        (
            "periodic32.txt: 1915 exact rational cases\nremainder64.txt: 10875"
            " exact rational cases\n"
        ),
    )


def test_decoding_and_rounding_are_inverse_for_finite_floats() raises:
    for bits in [
        UInt64(0),
        UInt64(1),
        UInt64(0x007FFFFF),
        UInt64(0x00800000),
        UInt64(0x3F800000),
        UInt64(0x7F7FFFFF),
    ]:
        assert_equal(rounded(exact(bits, 23, 8), 23, 8), bits)
    # 1 + 2**-24 is halfway between 1 and the next binary32; ties go even.
    var tie = Fraction(1) + Fraction.of(BigInt(1), BigInt(2) ** 24)
    assert_equal(rounded(tie, 23, 8), UInt64(0x3F800000))
    # A negative value sets the sign bit; past the range is infinite.
    assert_equal(rounded(-Fraction(1), 23, 8), UInt64(0xBF800000))
    assert_equal(rounded(Fraction(BigInt(2) ** 200), 23, 8), UInt64(0x7F800000))


def test_pairs_are_sorted_and_unique() raises:
    var cases = pairs(23, 8)
    assert_equal(len(cases), 1915)
    for index in range(1, len(cases)):
        var before = cases[index - 1]
        var after = cases[index]
        assert_true(
            before[0] < after[0]
            or (before[0] == after[0] and before[1] < after[1])
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
