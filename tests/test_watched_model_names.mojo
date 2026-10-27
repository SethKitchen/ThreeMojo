# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The watched model names stay in historical order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._watched_model_names import watched_model_names


def test_model_names_precede_removed_search_names() raises:
    """Six model names come before the twelve removed search names."""
    var doc = PyJson.parse(watched_model_names())
    assert_equal(doc.length(doc.root), 18)
    assert_equal(doc.text(doc.item(doc.root, 0)), "curve_objective_model")
    assert_equal(doc.text(doc.item(doc.root, 5)), "_objective_recheck_room")
    assert_equal(doc.text(doc.item(doc.root, 6)), "cached_model")
    assert_equal(doc.text(doc.item(doc.root, 17)), "packed_model")


def main() raises:
    """Run the watched-name tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
