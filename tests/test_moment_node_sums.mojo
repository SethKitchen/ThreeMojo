# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rounded node sums match the stored Gauss-Legendre pin."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_node_sums import moment_node_sums
from tools._python_json import PyJson


def _payload(expected_last: String) raises -> String:
    """Return the stored five-word node and weight pin.

    Args:
        expected_last: The pinned spelling of the last sum.

    Returns:
        A JSON object for the live Gauss-Legendre words.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var nodes = doc.new_list()
    var node_words = List[String]()
    node_words.append("13829709398833052265")
    node_words.append("13826397356768737029")
    node_words.append("0")
    node_words.append("4603025319913961221")
    node_words.append("4606337361978276457")
    for word in node_words:
        doc.append(nodes, doc.new_str(word))
    doc.set(root, "nodes", nodes)
    var weights = doc.new_list()
    var weight_words = List[String]()
    weight_words.append("4597704210940560269")
    weight_words.append("4602293827526345052")
    weight_words.append("4603299315121306847")
    weight_words.append("4602293827526345052")
    weight_words.append("4597704210940560269")
    for word in weight_words:
        doc.append(weights, doc.new_str(word))
    doc.set(root, "weights", weights)
    var expected = doc.new_list()
    var expected_words = List[String]()
    expected_words.append("0x3FB80498FD662CB8")
    expected_words.append("0x3FDD89B804CC91F6")
    expected_words.append("0x3FF0000000000000")
    expected_words.append("0x3FF89D91FECCDB82")
    expected_words.append(expected_last)
    for word in expected_words:
        doc.append(expected, doc.new_str(word))
    doc.set(root, "expected", expected)
    doc.set(root, "message", doc.new_str("rounded 1 + node words changed"))
    doc.root = root
    return doc.dumps()


def test_rounded_node_sums_match_their_fractions() raises:
    """The zero node rounds to one, and the other sums keep their fractions."""
    var result = PyJson.parse(moment_node_sums(_payload("0x3FFE7FB670299D34")))
    assert_equal(result.length(result.root), 5)
    assert_equal(
        result.text(result.item(result.root, 0)),
        "845056821740951/9007199254740992",
    )
    assert_equal(
        result.text(result.item(result.root, 1)),
        "4157098886056187/9007199254740992",
    )
    assert_equal(result.text(result.item(result.root, 2)), "1")
    assert_equal(
        result.text(result.item(result.root, 3)),
        "3464324905856449/2251799813685248",
    )
    assert_equal(
        result.text(result.item(result.root, 4)),
        "2146167710967629/1125899906842624",
    )


def test_a_changed_node_sum_is_refused() raises:
    """A different last pin is the stored-sum failure."""
    with assert_raises(contains="rounded 1 + node words changed"):
        _ = moment_node_sums(_payload("0x0000000000000000"))


def test_a_short_node_list_is_refused() raises:
    """Fewer than five nodes keeps the array-shape failure."""
    var doc = PyJson.parse(_payload("0x3FFE7FB670299D34"))
    var nodes = doc.new_list()
    doc.append(nodes, doc.new_str("0"))
    doc.set(doc.root, "nodes", nodes)
    with assert_raises(contains="wrong constant-array shape"):
        _ = moment_node_sums(doc.dumps())


def main() raises:
    """Run the rounded node-sum tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
