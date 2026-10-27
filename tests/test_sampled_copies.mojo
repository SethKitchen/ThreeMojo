# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled copy list and rename map stay in historical order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_copies import sampled_copies


def test_the_eight_copies_keep_their_names() raises:
    """The copy order and the projected names stay reviewed."""
    var doc = PyJson.parse(sampled_copies())
    var copies = doc.at(doc.root, "copies")
    var names = doc.at(doc.root, "names")
    assert_equal(doc.length(copies), 8)
    assert_equal(doc.text(doc.item(copies, 0)), "_atan_branch")
    assert_equal(doc.text(doc.item(copies, 7)), "_sample_jet")
    assert_equal(doc.text(doc.at(names, "_atan_branch")), "_atan_value_branch")
    assert_equal(doc.text(doc.at(names, "_sinc_jet")), "_sinc_value")
    assert_equal(
        doc.text(doc.at(names, "_arc_offset_jet")), "_arc_offset_value"
    )
    assert_equal(
        doc.text(doc.at(names, "_constant_sincos_jet")),
        "_constant_sincos_value",
    )
    assert_equal(doc.length(names), 16)


def main() raises:
    """Run the sampled copy tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
