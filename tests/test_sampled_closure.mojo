# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled reference names stay apart from the graph digests."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_closure import sampled_closure


def test_sampled_reference_names_stay_in_reviewed_order() raises:
    """Bounds, trig, and the interval stay ahead of the closure groups."""
    var doc = PyJson.parse(sampled_closure())
    var names = doc.at(doc.root, "reference_names")
    assert_equal(doc.length(names), 3)
    assert_equal(doc.text(doc.item(names, 0)), "curve_bounds.mojo")
    assert_equal(doc.text(doc.item(names, 1)), "curve_trig.mojo")
    assert_equal(doc.text(doc.item(names, 2)), "curve_interval.mojo")
    assert_equal(doc.text(doc.at(doc.root, "reviewed")), "curve_bounds.mojo")
    assert_equal(doc.text(doc.at(doc.root, "primitive")), "curve_interval.mojo")
    assert_equal(doc.text(doc.at(doc.root, "syntax")), "curve_trig.mojo")
    var groups = doc.at(doc.root, "groups")
    assert_equal(doc.text(doc.item(groups, 0)), "stored_arithmetic")
    assert_equal(doc.text(doc.item(groups, 1)), "canonical_accumulation")
    assert_equal(
        doc.text(doc.at(doc.root, "closure")), "wrong reference-module closure"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "primitive_message")),
        (
            "Jet primitive graph changed; renewed derivative-independence"
            " review required"
        ),
    )


def main() raises:
    """Run the sampled closure tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
