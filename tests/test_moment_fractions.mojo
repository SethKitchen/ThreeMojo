# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment fraction texts stay with their arrays."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_fractions import moment_fraction_groups
from tools._python_json import PyJson


def _payload() raises -> String:
    """Return two array groups.

    Returns:
        JSON for `1.0`, then `0.5` and `2.0`.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var groups = doc.new_list()
    var first = doc.new_dict()
    doc.set(first, "name", doc.new_str("_NODES"))
    var first_words = doc.new_list()
    doc.append(first_words, doc.new_str("4607182418800017408"))
    doc.set(first, "words", first_words)
    doc.append(groups, first)
    var second = doc.new_dict()
    doc.set(second, "name", doc.new_str("_WEIGHTS"))
    var second_words = doc.new_list()
    doc.append(second_words, doc.new_str("4602678819172646912"))
    doc.append(second_words, doc.new_str("4611686018427387904"))
    doc.set(second, "words", second_words)
    doc.append(groups, second)
    doc.set(root, "groups", groups)
    doc.set(root, "invalid", doc.new_str("invalid UInt64 word"))
    doc.root = root
    return doc.dumps()


def test_fraction_texts_stay_with_their_arrays() raises:
    """`1.0`, `0.5`, and `2.0` stay in the groups that supplied them."""
    var result = PyJson.parse(moment_fraction_groups(_payload()))
    var nodes = result.at(result.root, "_NODES")
    var weights = result.at(result.root, "_WEIGHTS")
    assert_equal(result.length(nodes), 1)
    assert_equal(result.text(result.item(nodes, 0)), "1")
    assert_equal(result.length(weights), 2)
    assert_equal(result.text(result.item(weights, 0)), "1/2")
    assert_equal(result.text(result.item(weights, 1)), "2")


def test_a_malformed_word_is_refused() raises:
    """A non-decimal word keeps the invalid-word text."""
    var payload = _payload().replace("4607182418800017408", "nope")
    with assert_raises(contains="invalid UInt64 word"):
        _ = moment_fraction_groups(payload)


def test_a_nonfinite_word_is_refused() raises:
    """An infinity encoding is not a stored fraction."""
    var payload = _payload().replace(
        "4607182418800017408", "9218868437227405312"
    )
    with assert_raises(contains="nonfinite binary64 word"):
        _ = moment_fraction_groups(payload)


def main() raises:
    """Run the moment fraction tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
