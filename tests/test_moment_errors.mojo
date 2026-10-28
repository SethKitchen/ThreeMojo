# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A stored decimal word keeps its sign, count, and constant error."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_errors import (
    classified_decimal_word,
    signed_classified_word,
    constant_error_text,
    decimal_word_result,
    signed_zero_word,
)


def test_a_negative_zero_token_is_marked() raises:
    """Only a zero fraction with a leading minus is a signed zero."""
    assert_equal(signed_zero_word('{"token":"-0.0","zero":true}'), "true")
    assert_equal(signed_zero_word('{"token":"0.0","zero":true}'), "false")
    assert_equal(signed_zero_word('{"token":"-1","zero":false}'), "false")
    assert_equal(signed_zero_word('{"token":"1","zero":false}'), "false")


def test_a_decimal_word_result_keeps_one_word() raises:
    """One word is returned, and an unsupported token asks for the fallback."""
    assert_equal(
        decimal_word_result('{"words":["9223372036854775808"]}'),
        "9223372036854775808",
    )
    assert_equal(
        decimal_word_result('{"error":"unsupported decimal word"}'), "nearest"
    )
    with assert_raises(contains="binary64 overflow"):
        _ = decimal_word_result('{"words":["1","2"]}')
    with assert_raises(contains="spiral moment word: bad literal"):
        _ = decimal_word_result('{"error":"spiral moment word: bad literal"}')


def test_a_constant_routing_error_names_the_declaration() raises:
    """Routing failures become a malformed declaration, and other text stays."""
    assert_equal(
        constant_error_text(
            '{"message":"unsupported top-level source'
            ' routing","name":"_GL_NODES"}'
        ),
        "malformed constant declaration: _GL_NODES",
    )
    assert_equal(
        constant_error_text(
            '{"message":"incomplete top-level source'
            ' routing","name":"_PHASE_LIMIT"}'
        ),
        "malformed constant declaration: _PHASE_LIMIT",
    )
    assert_equal(
        constant_error_text('{"message":"other failure","name":"_GL_NODES"}'),
        "other failure",
    )


def test_one_literal_is_rounded_and_classified() raises:
    """`1.0` is rounded and returned as its one decimal word."""
    assert_equal(classified_decimal_word("1.0"), "4607182418800017408")


def test_a_bad_literal_fails_before_classification() raises:
    """A malformed literal fails before the word count is checked."""
    with assert_raises(contains="spiral moment word: unsupported decimal word"):
        _ = classified_decimal_word("nope")


def test_a_signed_zero_is_marked_before_rounding() raises:
    """A negative zero token is marked before the literal is rounded."""
    assert_equal(
        signed_classified_word('{"token":"-nope","zero":true}'), "signed"
    )


def test_an_unsupported_literal_is_nearest_before_another_failure() raises:
    """An unsupported literal is nearest, and it is not rounded first."""
    assert_equal(
        signed_classified_word('{"token":"nope","zero":false}'), "nearest"
    )


def test_an_unsigned_literal_is_still_rounded() raises:
    """A non-zero fraction still rounds `1.0` after the sign check."""
    assert_equal(
        signed_classified_word('{"token":"1.0","zero":false}'),
        "4607182418800017408",
    )


def main() raises:
    """Run the moment error tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
