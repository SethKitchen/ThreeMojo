# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The optional-runtime module names stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._optional_runtime_modules import optional_runtime_modules
from tools._python_json import PyJson


def test_five_modules_stay_in_reviewed_order() raises:
    """Support, the objective model, dispatch, and the two grouped modules stay in order.
    """
    var doc = PyJson.parse(optional_runtime_modules())
    assert_equal(doc.length(doc.root), 5)
    assert_equal(doc.text(doc.item(doc.root, 0)), "curve_minimizer_support")
    assert_equal(doc.text(doc.item(doc.root, 1)), "curve_objective_model")
    assert_equal(doc.text(doc.item(doc.root, 2)), "curve_sample_dispatch")
    assert_equal(doc.text(doc.item(doc.root, 3)), "spiral_grouped_lane")
    assert_equal(
        doc.text(doc.item(doc.root, 4)), "spiral_grouped_roundoff_proof"
    )


def main() raises:
    """Run the optional-runtime module tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
