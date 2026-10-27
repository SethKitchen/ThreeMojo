# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment constant arrays match their pins in one check."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_arrays import moment_arrays
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


def main() raises:
    """Run the moment array tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
