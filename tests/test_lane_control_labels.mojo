# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The lane-control labels and the frozen reference prefix stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._lane_control_labels import lane_control_labels
from tools._python_json import PyJson


def test_lane_control_labels_keep_the_reference_prefix() raises:
    """The frozen name is `def _reference` plus the original name."""
    var doc = PyJson.parse(lane_control_labels())
    assert_equal(doc.length(doc.root), 12)
    assert_equal(doc.key(doc.root, 0), "successor")
    assert_equal(
        doc.text(doc.at(doc.root, "successor")),
        "lane-control successor module changed",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "before")),
        "lane-control before declaration drift",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "after")),
        "lane-control after declaration drift",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "frozen")),
        "lane-control frozen predecessor changed",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "premise")),
        "lane-control guarded premise changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "producer")),
        "lane-control IEEE producer module changed: ",
    )
    assert_equal(doc.text(doc.at(doc.root, "definition")), "def ")
    assert_equal(doc.text(doc.at(doc.root, "call")), "(")
    assert_equal(doc.text(doc.at(doc.root, "reference")), "_reference")
    assert_equal(
        doc.text(doc.at(doc.root, "pass")), "Lane control-flow migration: PASS"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "record")),
        "73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "predecessor")),
        "33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315",
    )


def main() raises:
    """Run the lane-control label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
