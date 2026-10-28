# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral-moment words use exact even rounding."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_json import PyJson
from tools._spiral_moment_words import (
    INFINITY,
    MAX_FINITE,
    SIGN,
    bracket,
    decimal_integers_json,
    rounded_array_words,
    rounded_node_sums_from_decimals,
    decimal_word,
    fraction_of_word,
    fraction_texts,
    nearest_even,
    parsed_table_integers,
    verify_bracket,
)


def test_fraction_spellings_match_binary64_words() raises:
    """Zero, one, and a negative one keep their exact spellings."""
    var words = List[UInt64]()
    words.append(0)
    words.append(SIGN)
    words.append(UInt64(0x3FF0000000000000))
    words.append(UInt64(0xBFF0000000000000))
    var texts = fraction_texts(words)
    assert_equal(texts[0], "0")
    assert_equal(texts[1], "0")
    assert_equal(texts[2], "1")
    assert_equal(texts[3], "-1")
    var bad = List[UInt64]()
    bad.append(UInt64(0x7FF0000000000000))
    with assert_raises(contains="nonfinite binary64 word"):
        _ = fraction_texts(bad)


def test_stored_words_round_trip() raises:
    """Each finite word is its own tight bracket."""
    var words = List[UInt64]()
    words.append(0)
    words.append(1)
    words.append((UInt64(1) << 52) - 1)
    words.append(UInt64(1) << 52)
    words.append(0x3FEFFFFFFFFFFFFF)
    words.append(0x3FF0000000000000)
    words.append(0x3FF0000000000001)
    words.append(MAX_FINITE)
    for word in words:
        for sign in range(2):
            var signed = word
            if sign == 1:
                signed = word | SIGN
            var value = fraction_of_word(signed)
            var pair = bracket(value)
            if value.is_zero():
                assert_equal(pair[0], SIGN)
                assert_equal(pair[1], UInt64(0))
            else:
                assert_equal(pair[0], signed)
                assert_equal(pair[1], signed)


def test_halfway_rounding_is_even() raises:
    """A halfway value keeps the even encoding."""
    var lows = List[UInt64]()
    lows.append(0)
    lows.append(1)
    lows.append((UInt64(1) << 52) - 1)
    lows.append(UInt64(1) << 52)
    lows.append(0x3FEFFFFFFFFFFFFF)
    lows.append(0x3FF0000000000000)
    lows.append(0x3FF0000000000001)
    for low in lows:
        var mid = (
            fraction_of_word(low) + fraction_of_word(low + 1)
        ) / Fraction(2)
        var even = low
        if low % 2 != 0:
            even = low + 1
        assert_equal(nearest_even(mid), even)
        assert_equal(nearest_even(-mid), even | SIGN)


def test_decimal_sign_and_exact_rounding() raises:
    """Signed zero and one tenth keep their reviewed encodings."""
    assert_equal(decimal_word("-0.0"), SIGN)
    assert_equal(decimal_word("0.0"), UInt64(0))
    assert_equal(decimal_word("0.1"), UInt64(0x3FB999999999999A))
    assert_equal(decimal_word("-0.1"), UInt64(0xBFB999999999999A))
    assert_equal(decimal_word("1e1"), UInt64(0x4024000000000000))
    assert_equal(decimal_word("-1e1"), UInt64(0xC024000000000000))
    with assert_raises(contains="unsupported"):
        _ = decimal_word("no")
    with assert_raises(contains="unsupported"):
        _ = decimal_word("1e")
    with assert_raises(contains="unsupported"):
        _ = decimal_word("1.2.3")


def test_subnormal_underflow_brackets() raises:
    """The smallest positive fraction sits between 0 and the minimum."""
    var tiny = Fraction.of(BigInt(1), BigInt.power_of_two(1076))
    var pair = bracket(tiny)
    assert_equal(pair[0], UInt64(0))
    assert_equal(pair[1], UInt64(1))
    var negative = bracket(-tiny)
    assert_equal(negative[0], SIGN | 1)
    assert_equal(negative[1], SIGN)


def test_bad_and_nonfinite_words_are_refused() raises:
    """A nonfinite word and an overflow are refused."""
    var words = List[UInt64]()
    words.append(INFINITY)
    words.append(INFINITY + 1)
    words.append(SIGN | INFINITY)
    for word in words:
        with assert_raises(contains="nonfinite"):
            _ = fraction_of_word(word)
    with assert_raises(contains="overflow"):
        _ = bracket(fraction_of_word(MAX_FINITE) * Fraction(2))


def test_a_wide_endpoint_is_refused() raises:
    """A bracket wider than one step is refused."""
    with assert_raises(contains="greatest-below"):
        verify_bracket(
            Fraction(1), UInt64(0x3FEFFFFFFFFFFFFF), UInt64(0x3FF0000000000001)
        )


def _table_payload(source: String, count: Int) raises -> String:
    """Return one stored-table integer check.

    Args:
        source: The table text.
        count: The required word count.

    Returns:
        JSON with `source` and `count`.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(source))
    doc.set(root, "count", doc.new_int(count))
    doc.root = root
    return doc.dumps()


def test_a_missing_table_fails_before_the_integers() raises:
    """A missing declaration fails before the words are read as integers."""
    with assert_raises(contains="missing or malformed table declaration"):
        _ = parsed_table_integers(_table_payload("nope", 1))


def test_one_table_word_is_read_as_an_integer() raises:
    """`1.0` in a one-word table becomes its binary64 integer."""
    var source = (
        "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, 1] = [\n"
        + "UInt64(0x3FF0000000000000),\n"
        + "]\n"
    )
    var result = PyJson.parse(parsed_table_integers(_table_payload(source, 1)))
    assert_equal(result.length(result.root), 1)
    assert_equal(
        result.text(result.item(result.root, 0)), "4607182418800017408"
    )


def _decimal_sums(
    node: String, weight: String, node_count: Int, weight_count: Int
) raises -> String:
    """Return decimal node and weight lists.

    Args:
        node: The node word.
        weight: The weight word.
        node_count: How many node words to write.
        weight_count: How many weight words to write.

    Returns:
        JSON with `nodes` and `weights`.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var nodes = doc.new_list()
    var index = 0
    while index < node_count:
        doc.append(nodes, doc.new_str(node))
        index += 1
    var weights = doc.new_list()
    index = 0
    while index < weight_count:
        doc.append(weights, doc.new_str(weight))
        index += 1
    doc.set(root, "nodes", nodes)
    doc.set(root, "weights", weights)
    doc.root = root
    return doc.dumps()


def test_a_bad_weight_word_fails_before_the_sum_shape() raises:
    """A malformed weight fails before the five-word shape is checked."""
    with assert_raises(contains="invalid UInt64 word"):
        _ = rounded_node_sums_from_decimals(_decimal_sums("0", "nope", 5, 1))


def test_spelled_words_still_check_the_zeroth_moment() raises:
    """Five zero nodes and five zero weights still refuse the weight sum."""
    with assert_raises(
        contains="stored zeroth moment must not be normalized to one"
    ):
        _ = rounded_node_sums_from_decimals(_decimal_sums("0", "0", 5, 5))


def test_a_missing_array_fails_before_rounding() raises:
    """A missing array fails before its literals are rounded."""
    with assert_raises(contains="missing or ambiguous constant array: _NODES"):
        _ = rounded_array_words(
            '{"source":"def f():\\n pass\\n","name":"_NODES","size":2}'
        )


def test_one_array_is_read_and_rounded() raises:
    """`1.0` and `2.0` become their binary64 integers."""
    var source = (
        "comptime _NODES: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(source))
    doc.set(root, "name", doc.new_str("_NODES"))
    doc.set(root, "size", doc.new_int(2))
    doc.root = root
    var result = PyJson.parse(rounded_array_words(doc.dumps()))
    assert_equal(
        result.text(result.item(result.root, 0)), "4607182418800017408"
    )
    assert_equal(
        result.text(result.item(result.root, 1)), "4611686018427387904"
    )


def test_a_bad_literal_fails_before_the_integer_read() raises:
    """A malformed literal fails before the rounded words are read."""
    with assert_raises(contains="unsupported decimal word"):
        _ = decimal_integers_json('["nope"]')


def test_one_decimal_literal_is_read_as_an_integer() raises:
    """`1.0` rounds to its binary64 integer."""
    var result = PyJson.parse(decimal_integers_json('["1.0"]'))
    assert_equal(result.length(result.root), 1)
    assert_equal(
        result.text(result.item(result.root, 0)), "4607182418800017408"
    )


def main() raises:
    """Run the spiral-moment word tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
