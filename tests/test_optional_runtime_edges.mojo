# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The lane-search fragment list keeps historical order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._optional_runtime_edges import search_edge_payload
from tools._python_json import PyJson


def _length(mode: String) raises -> Int:
    """Return the number of checks for `mode`.

    Args:
        mode: `fresh` or `search`.

    Returns:
        The list length.

    Raises:
        Error: `mode` is not recognized.
    """
    var doc = PyJson.parse(search_edge_payload("fn", "_run", mode))
    return doc.length(doc.root)


def test_fresh_edges_precede_the_search_predicates() raises:
    """Search mode keeps the five fresh checks and adds eight predicates."""
    assert_equal(_length("fresh"), 5)
    assert_equal(_length("search"), 13)
    var doc = PyJson.parse(
        search_edge_payload("body", "_run_lane_search", "search")
    )
    assert_equal(doc.text(doc.at(doc.item(doc.root, 0), "kind")), "fresh")
    assert_equal(doc.text(doc.at(doc.item(doc.root, 0), "label")), "fresh")
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 0), "name")), "_run_lane_search"
    )
    assert_equal(doc.text(doc.at(doc.item(doc.root, 0), "source")), "body")
    assert_equal(Int(doc.text(doc.at(doc.item(doc.root, 0), "expected"))), 1)
    assert_equal(doc.text(doc.at(doc.item(doc.root, 4), "kind")), "sequence")
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 9), "kind")),
        "sequence",
    )
    assert_equal(doc.text(doc.at(doc.item(doc.root, 12), "kind")), "expression")
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 12), "label")),
        "split predecessor preserves every stored owner station",
    )


def test_a_search_edge_mode_must_be_fresh_or_search() raises:
    """Any other mode is refused before a check is built."""
    with assert_raises(contains="runtime search edge mode changed"):
        _ = search_edge_payload("fn", "_run", "both")


def main() raises:
    """Run the lane-search edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
