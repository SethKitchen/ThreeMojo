# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The three sampled declarations keep their reviewed text."""

from std.testing import TestSuite, assert_true

from tools._python_json import PyJson
from tools._sampled_declarations import sampled_declarations


def test_the_three_sampled_declarations_are_present() raises:
    """Each reviewed declaration is a non-empty function."""
    var doc = PyJson.parse(sampled_declarations())
    var names = List[String]()
    names.append("_uncertain_value")
    names.append("_sampled_lane_value_bound")
    names.append("_lane_value_bound")
    for name in names:
        var text = doc.text(doc.at(doc.root, name))
        assert_true(text.startswith("def " + name))
        assert_true(text.byte_length() > 40)


def main() raises:
    """Run the sampled declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
