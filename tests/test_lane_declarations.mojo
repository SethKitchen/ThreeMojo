# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Lane-control declarations stay in the requested order."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._lane_declarations import lane_declarations
from tools._python_json import PyJson


def _payload(name: String, owner_name: String) raises -> String:
    """Return two declaration pins.

    Args:
        name: The first function name.
        owner_name: An owner for the first function. Empty means none.

    Returns:
        A JSON list.

    Raises:
        Error: The payload cannot be written.
    """
    var source = "def f():\n    return 1\n\ndef g():\n    return 2\n"
    var doc = PyJson()
    var rows = doc.new_list()
    var first = doc.new_dict()
    doc.set(first, "source", doc.new_str(source))
    doc.set(first, "name", doc.new_str(name))
    var owners = doc.new_list()
    if owner_name.byte_length() > 0:
        doc.append(owners, doc.new_str(owner_name))
    doc.set(first, "owner", owners)
    doc.append(rows, first)
    var second = doc.new_dict()
    doc.set(second, "source", doc.new_str(source))
    doc.set(second, "name", doc.new_str("g"))
    doc.set(second, "owner", doc.new_list())
    doc.append(rows, second)
    doc.root = rows
    return doc.dumps()


def test_lane_declarations_keep_their_order() raises:
    """`f` comes back before `g`."""
    var doc = PyJson.parse(lane_declarations(_payload("f", "")))
    assert_equal(doc.length(doc.root), 2)
    assert_true(doc.text(doc.item(doc.root, 0)).find("return 1") >= 0)
    assert_true(doc.text(doc.item(doc.root, 1)).find("return 2") >= 0)
    assert_true(doc.text(doc.item(doc.root, 0)).find("return 2") < 0)


def test_a_missing_lane_declaration_is_refused() raises:
    """The first missing name is reported."""
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = lane_declarations(_payload("absent", ""))


def test_a_wrong_lane_owner_is_refused() raises:
    """A top-level function is not inside another struct."""
    with assert_raises(
        contains="guard caller owner/scope changed: f"
    ):
        _ = lane_declarations(_payload("f", "Nope"))


def main() raises:
    """Run the lane declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
