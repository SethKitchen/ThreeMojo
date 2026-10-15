# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The footprint-axis reference rounds as a 100-digit `Decimal` context.

The expected digits are what CPython 3.12's `decimal` printed.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools.reference_texture_axes import (
    parse_decimal,
    rounded,
    square_root,
    verify,
)


def test_the_fixture_verifies() raises:
    var outcome = verify("docs/fixtures/glsl614/footprint_axes.json")
    assert_equal(outcome[0], 0, outcome[1])
    assert_true(
        outcome[1].find(
            "PASS general_scale1: 9.271108627319336, 0.215723916888237\n"
        )
        >= 0
    )
    assert_true(
        outcome[1].endswith("Verified 55 exact-input singular-value fixtures\n")
    )


def test_a_changed_expectation_fails() raises:
    var text = Path("docs/fixtures/glsl614/footprint_axes.json").read_text()
    var changed = text.replace('"major": "16"', '"major": "16.0000001"')
    var path = mkdtemp() + "/footprint_axes.json"
    Path(path).write_text(changed)
    var outcome = verify(path)
    assert_equal(outcome[0], 1)
    assert_true(
        outcome[1].endswith("Independent expectation differs: axis16_1\n")
    )


def test_square_root_rounds_to_100_digits() raises:
    assert_true(
        square_root(Fraction(2))
        == parse_decimal(
            "1.41421356237309504880168872420969807856967187537694807317667"
            "9737990732478462107038850387534327641573"
        )
    )
    assert_true(square_root(parse_decimal("1E-40")) == parse_decimal("1E-20"))
    assert_true(square_root(Fraction(0)).is_zero())


def test_rounding_keeps_ties_even() raises:
    assert_true(
        rounded(Fraction.of(BigInt(1), BigInt(3)))
        == parse_decimal("0." + "3" * 100)
    )
    # 1 followed by 99 zeros and a 5 is a tie: it rounds down to even.
    assert_true(
        rounded(parse_decimal("1" + "0" * 99 + "5")) == parse_decimal("1E+100")
    )
    assert_true(
        rounded(parse_decimal("1" + "0" * 98 + "15"))
        == parse_decimal("1" + "0" * 98 + "2E+1")
    )
    assert_true(rounded(parse_decimal("-2.5")) == parse_decimal("-2.5"))


def test_parse_decimal_refuses_other_text() raises:
    for text in ["", "1.2.3", "x", "1x"]:
        var refused = False
        try:
            _ = parse_decimal(text)
        except:
            refused = True
        assert_true(refused, text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
