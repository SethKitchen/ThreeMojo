# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed cleanup declarations stay in source order."""

from std.testing import TestSuite, assert_equal

from tools._cleanup_declarations import cleanup_declarations
from tools._python_json import PyJson


def test_cleanup_declarations_stay_with_their_sources() raises:
    """Line, arc, bounds, center, and outward keep their owners."""
    var doc = PyJson.parse(cleanup_declarations())
    assert_equal(doc.key(doc.root, 0), "junction")
    assert_equal(doc.key(doc.root, 1), "unreviewed")
    assert_equal(doc.key(doc.root, 2), "declarations")
    assert_equal(
        doc.text(doc.at(doc.root, "junction")),
        "extensions/carla/junction_bounds.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "unreviewed")),
        "unreviewed complete successor: ",
    )
    var rows = doc.at(doc.root, "declarations")
    assert_equal(doc.length(rows), 5)
    assert_equal(doc.text(doc.at(doc.item(rows, 0), "key")), "line")
    assert_equal(doc.text(doc.at(doc.item(rows, 0), "source")), "0")
    assert_equal(
        doc.text(doc.at(doc.item(rows, 0), "name")),
        "_rounded_line_axis_context",
    )
    assert_equal(doc.length(doc.at(doc.item(rows, 0), "owner")), 0)
    assert_equal(doc.text(doc.at(doc.item(rows, 1), "key")), "arc")
    assert_equal(
        doc.text(doc.at(doc.item(rows, 1), "name")), "_rounded_arc_context"
    )
    var bounds = doc.item(rows, 2)
    assert_equal(doc.text(doc.at(bounds, "source")), "1")
    assert_equal(doc.text(doc.at(bounds, "name")), "bounds")
    assert_equal(doc.text(doc.item(doc.at(bounds, "owner"), 0)), "_RoundedBox")
    var center = doc.item(rows, 3)
    assert_equal(doc.text(doc.at(center, "name")), "center")
    assert_equal(doc.text(doc.item(doc.at(center, "owner"), 0)), "_RoundedArc")
    var outward = doc.item(rows, 4)
    assert_equal(doc.text(doc.at(outward, "source")), "2")
    assert_equal(doc.text(doc.at(outward, "name")), "_outward_float")
    assert_equal(doc.text(doc.at(outward, "key")), "outward")


def main() raises:
    """Run the cleanup declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
