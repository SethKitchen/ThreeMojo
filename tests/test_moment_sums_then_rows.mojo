# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The rounded node sums are checked before the moment rows."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_moment_gate import moment_sums_then_rows


def _words(mut doc: PyJson, values: List[String]) -> Int:
    """Return a JSON list of decimal words.

    Args:
        doc: The document that owns the list.
        values: The decimal spellings.

    Returns:
        The list node.
    """
    var rows = doc.new_list()
    for value in values:
        doc.append(rows, doc.new_str(value))
    return rows


def _payload(expected_last: String, cosine: String) raises -> String:
    """Return one sums-then-rows payload.

    Args:
        expected_last: The pinned spelling of the last node sum.
        cosine: The first cosine word. The other cosine and sine words are
            zero.

    Returns:
        The JSON payload.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var nodes = List[String]()
    nodes.append("13829709398833052265")
    nodes.append("13826397356768737029")
    nodes.append("0")
    nodes.append("4603025319913961221")
    nodes.append("4606337361978276457")
    doc.set(root, "nodes", _words(doc, nodes))
    var weights = List[String]()
    weights.append("4597704210940560269")
    weights.append("4602293827526345052")
    weights.append("4603299315121306847")
    weights.append("4602293827526345052")
    weights.append("4597704210940560269")
    doc.set(root, "weights", _words(doc, weights))
    var expected = List[String]()
    expected.append("0x3FB80498FD662CB8")
    expected.append("0x3FDD89B804CC91F6")
    expected.append("0x3FF0000000000000")
    expected.append("0x3FF89D91FECCDB82")
    expected.append(expected_last)
    doc.set(root, "expected", _words(doc, expected))
    doc.set(root, "message", doc.new_str("rounded 1 + node words changed"))
    var trig = List[String]()
    trig.append(cosine)
    var index = 0
    while index < 10:
        trig.append("0")
        index += 1
    doc.set(root, "cosine", _words(doc, trig))
    var sine = List[String]()
    index = 0
    while index < 11:
        sine.append("0")
        index += 1
    doc.set(root, "sine", _words(doc, sine))
    doc.root = root
    return doc.dumps()


def test_a_changed_node_sum_fails_before_the_rows() raises:
    """A wrong sum pin fails before a malformed cosine word is read."""
    with assert_raises(contains="rounded 1 + node words changed"):
        _ = moment_sums_then_rows(_payload("0x0000000000000000", "nope"))


def test_matching_sums_return_the_moment_rows() raises:
    """A matching sum pin returns the sums and then the derived rows."""
    var doc = PyJson.parse(
        moment_sums_then_rows(_payload("0x3FFE7FB670299D34", "0"))
    )
    assert_equal(doc.key(doc.root, 0), "sums")
    assert_equal(doc.key(doc.root, 1), "rows")
    assert_equal(doc.length(doc.at(doc.root, "sums")), 5)
    assert_equal(doc.text(doc.item(doc.at(doc.root, "sums"), 2)), "1")
    assert_equal(doc.length(doc.at(doc.root, "rows")), 64)


def main() raises:
    """Run the node-sum and moment-row tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
