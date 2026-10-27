# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The Sum2 module names and caller comparisons stay in reviewed order."""

from std.testing import TestSuite, assert_equal, assert_true

from tools._python_json import MISSING, PyJson
from tools._sum2_plan import sum2_plan


def test_sum2_modules_and_caller_comparisons_stay_reviewed() raises:
    """Four modules feed five caller comparisons and three helper bindings."""
    var doc = PyJson.parse(sum2_plan())
    assert_equal(doc.key(doc.root, 0), "modules")
    assert_equal(doc.key(doc.root, 1), "graphs")
    assert_equal(doc.key(doc.root, 2), "helpers")
    var modules = doc.at(doc.root, "modules")
    assert_equal(doc.length(modules), 4)
    assert_equal(doc.text(doc.item(modules, 0)), "curve_sum2")
    assert_equal(doc.text(doc.item(modules, 1)), "lane_geometry")
    assert_equal(doc.text(doc.item(modules, 2)), "curve_bounds")
    assert_equal(doc.text(doc.item(modules, 3)), "spiral_roundoff_proof")
    var graphs = doc.at(doc.root, "graphs")
    assert_equal(doc.length(graphs), 5)
    var first = doc.item(graphs, 0)
    assert_equal(doc.text(doc.at(first, "slice")), "_sum2_update")
    assert_equal(doc.text(doc.at(first, "checkpoint")), "helper")
    assert_equal(doc.text(doc.at(first, "message")), "Sum2 recurrence changed")
    var second = doc.item(graphs, 1)
    assert_equal(doc.text(doc.at(second, "rename")), "_sum2_error")
    assert_equal(
        doc.text(doc.at(second, "message")),
        "Sum2 checked arithmetic leaf changed",
    )
    var third = doc.item(graphs, 2)
    assert_equal(doc.find(third, "slice"), MISSING)
    assert_true(doc.flag(doc.at(third, "drop_first")))
    assert_equal(
        doc.text(doc.at(third, "expect_first")), "_require_sum2_environment()"
    )
    assert_equal(doc.text(doc.at(third, "left_name")), "_lane_spiral")
    var fourth = doc.item(graphs, 3)
    assert_equal(doc.find(fourth, "slice"), MISSING)
    assert_equal(doc.find(fourth, "rename"), MISSING)
    assert_equal(doc.text(doc.at(fourth, "checkpoint")), "envelope")
    assert_equal(
        doc.text(doc.at(fourth, "message")),
        "Sum2 complete caller graph changed: _sum2_envelope_error",
    )
    var fifth = doc.item(graphs, 4)
    assert_equal(doc.find(fifth, "drop_first"), MISSING)
    assert_equal(doc.text(doc.at(fifth, "checkpoint")), "eligibility")
    assert_equal(
        doc.text(doc.at(fifth, "right_name")), "_try_spiral_roundoff_envelope"
    )
    var helpers = doc.at(doc.root, "helpers")
    assert_equal(doc.key(helpers, 0), "lane")
    assert_equal(doc.key(helpers, 1), "bounds")
    assert_equal(doc.key(helpers, 2), "roundoff")
    assert_equal(doc.text(doc.at(helpers, "lane")), "lane_geometry")
    assert_equal(doc.text(doc.at(helpers, "bounds")), "curve_bounds")
    assert_equal(doc.text(doc.at(helpers, "roundoff")), "spiral_roundoff_proof")
    assert_equal(doc.text(doc.at(doc.root, "stored_half")), "_stored_half")
    assert_equal(doc.text(doc.at(doc.root, "half_key")), "bounds")
    assert_equal(doc.text(doc.at(doc.root, "interval_key")), "interval")
    assert_equal(
        doc.text(doc.at(doc.root, "spiral_begin")), "def _spiral_expression["
    )
    assert_equal(doc.text(doc.at(doc.root, "spiral_end")), "def _sample_index(")
    assert_equal(
        doc.text(doc.at(doc.root, "helper_sha")),
        "41995592963bae61a2b690b465bdad6c759b02ddbe98141ba5da30d0df5d5c8e",
    )


def main() raises:
    """Run the Sum2 plan tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
