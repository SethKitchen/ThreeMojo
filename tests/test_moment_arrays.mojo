# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment constant arrays match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_arrays import moment_array_fractions, moment_arrays
from tools._python_json import PyJson


def _payload(source: String, expected_first: String) raises -> String:
    """Return one two-word array pin.

    Args:
        source: The module source.
        expected_first: The pinned spelling of the first word.

    Returns:
        A JSON list with one array.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    var item = doc.new_dict()
    doc.set(item, "name", doc.new_str("_NODES"))
    doc.set(item, "source", doc.new_str(source))
    doc.set(item, "size", doc.new_int(2))
    var expected = doc.new_list()
    doc.append(expected, doc.new_str(expected_first))
    doc.append(expected, doc.new_str("0x4000000000000000"))
    doc.set(item, "expected", expected)
    doc.set(
        item, "message", doc.new_str("stored constant words changed: _NODES")
    )
    doc.append(rows, item)
    doc.root = rows
    return doc.dumps()


def test_one_constant_array_returns_its_words() raises:
    """`1.0` and `2.0` become their binary64 words."""
    var source = (
        "comptime _NODES: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    var result = PyJson.parse(
        moment_arrays(_payload(source, "0x3FF0000000000000"))
    )
    var words = result.at(result.root, "_NODES")
    assert_equal(result.length(words), 2)
    assert_equal(result.text(result.item(words, 0)), "4607182418800017408")
    assert_equal(result.text(result.item(words, 1)), "4611686018427387904")


def test_a_missing_constant_array_names_itself() raises:
    """A missing declaration keeps the array name for the caller."""
    var source = (
        "comptime OTHER: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    with assert_raises(contains="stored array literal: _NODES"):
        _ = moment_arrays(_payload(source, "0x3FF0000000000000"))


def _checked_payload(source: String, name: String) raises -> String:
    """Return one array check with a required name.

    Args:
        source: The module source.
        name: The required array name.

    Returns:
        JSON with the array, its fraction message, and the name set.

    Raises:
        Error: The payload cannot be written.
    """
    var arrays = PyJson.parse(_payload(source, "0x3FF0000000000000"))
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "arrays", doc.adopt(arrays, arrays.root))
    doc.set(root, "invalid", doc.new_str("invalid UInt64 word"))
    var expected = doc.new_list()
    doc.append(expected, doc.new_str(name))
    doc.set(root, "names", expected)
    doc.set(root, "message", doc.new_str("stored array names changed"))
    doc.root = root
    return doc.dumps()


def test_array_fractions_keep_the_words_and_spellings() raises:
    """`1.0` and `2.0` keep their words and fraction spellings."""
    var source = (
        "comptime _NODES: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    var checked = PyJson.parse(
        moment_array_fractions(_checked_payload(source, "_NODES"))
    )
    var words = checked.at(checked.at(checked.root, "words"), "_NODES")
    var fractions = checked.at(checked.at(checked.root, "fractions"), "_NODES")
    assert_equal(checked.text(checked.item(words, 0)), "4607182418800017408")
    assert_equal(checked.text(checked.item(words, 1)), "4611686018427387904")
    assert_equal(checked.text(checked.item(fractions, 0)), "1")
    assert_equal(checked.text(checked.item(fractions, 1)), "2")


def test_a_missing_array_fails_before_the_name_set() raises:
    """A missing array fails before a wrong name set is checked."""
    var source = (
        "comptime OTHER: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    with assert_raises(contains="stored array literal: _NODES"):
        _ = moment_array_fractions(_checked_payload(source, "other"))


def test_a_wrong_name_set_fails_after_the_array() raises:
    """A matching array still refuses a different name set."""
    var source = (
        "comptime _NODES: Array[Float64, 2] = [\n    1.0,\n    2.0,\n]\n"
    )
    with assert_raises(contains="stored array names changed"):
        _ = moment_array_fractions(_checked_payload(source, "other"))


def main() raises:
    """Run the moment array tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
