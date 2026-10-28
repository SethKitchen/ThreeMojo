# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled graph digests stay in historical order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_graph_pins import (
    sampled_graph_pins,
    sampled_graphs_and_names,
)


def test_graph_digests_keep_their_reviewed_order() raises:
    """Reference modules stay first, then the primitive, then fourteen helpers.
    """
    var doc = PyJson.parse(sampled_graph_pins())
    assert_equal(doc.length(doc.root), 3)
    assert_equal(doc.key(doc.root, 0), "reference")
    assert_equal(doc.key(doc.root, 1), "primitive")
    assert_equal(doc.key(doc.root, 2), "shared")
    var reference = doc.at(doc.root, "reference")
    assert_equal(doc.length(reference), 3)
    assert_equal(doc.key(reference, 0), "curve_bounds.mojo")
    assert_equal(doc.key(reference, 1), "curve_trig.mojo")
    assert_equal(doc.key(reference, 2), "curve_interval.mojo")
    assert_equal(
        doc.text(doc.at(reference, "curve_bounds.mojo")),
        "51f99d745612d217762d8f39bde1ded5b269d239f05cb765532de631cc64791f",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "primitive")),
        "e2e0257a0f42a95bac586638fc5d532f4bc69b882127201bbf343006f2143484",
    )
    var shared = doc.at(doc.root, "shared")
    assert_equal(doc.length(shared), 14)
    assert_equal(doc.key(shared, 0), "curve_trig.mojo:_expression_polynomial")
    assert_equal(
        doc.key(shared, 13), "curve_bounds.mojo:_reference_jet_capture"
    )
    assert_equal(
        doc.text(doc.value(shared, 13)),
        "0ebd93d524b35c30cdd27fabc23dd40f1a53241477b0689c37b07b18bce5ad05",
    )


def test_reference_names_match_the_digest_keys() raises:
    """The closure names match the reference digest keys."""
    var checked = PyJson.parse(sampled_graphs_and_names())
    var graphs = checked.at(checked.root, "graphs")
    var closure = checked.at(checked.root, "closure")
    var reference = checked.at(graphs, "reference")
    var names = checked.at(closure, "reference_names")
    assert_equal(checked.length(reference), checked.length(names))


def main() raises:
    """Run the sampled graph digest tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
