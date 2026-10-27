# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored hexadecimal words become exact decimal integers."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._spiral_moment_words import hex_integers_json


def test_hex_words_keep_every_decimal_digit() raises:
    """Zero, a wide word, and a value past 2^53 keep their digits."""
    assert_equal(hex_integers_json("[]"), "[]")
    assert_equal(hex_integers_json('["0x0","0x1"]'), '["0","1"]')
    assert_equal(hex_integers_json('["0x100000000"]'), '["4294967296"]')
    assert_equal(
        hex_integers_json('["0xFFFFFFFFFFFFFFFF","0x3ff0000000000000"]'),
        '["18446744073709551615","4607182418800017408"]',
    )
    assert_equal(hex_integers_json('["0X0A"]'), '["10"]')


def test_a_malformed_hex_word_is_refused() raises:
    """An empty prefix or a non-digit fails before a later word is read."""
    with assert_raises(contains="malformed coefficient word"):
        _ = hex_integers_json('["0x"]')
    with assert_raises(contains="malformed coefficient word"):
        _ = hex_integers_json('["0x1","zz"]')


def main() raises:
    """Run the hexadecimal integer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
