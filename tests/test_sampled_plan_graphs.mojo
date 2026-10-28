# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled input plan is read before the graph pins."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_input_modules import sampled_plan_then_graphs


def test_the_input_plan_precedes_the_graph_pins() raises:
    """The modules and package stay ahead of the graph pins and closure."""
    var doc = PyJson.parse(sampled_plan_then_graphs())
    assert_equal(doc.key(doc.root, 0), "modules")
    assert_equal(doc.key(doc.root, 1), "package")
    assert_equal(doc.key(doc.root, 2), "graphs")
    assert_equal(doc.key(doc.root, 3), "closure")
    assert_equal(
        doc.text(doc.item(doc.at(doc.root, "modules"), 0)), "curve_bounds.mojo"
    )
    assert_equal(doc.length(doc.at(doc.root, "modules")), 4)
    assert_equal(doc.text(doc.at(doc.root, "package")), "extensions/carla")
    var graphs = doc.at(doc.root, "graphs")
    assert_equal(doc.key(graphs, 0), "reference")
    assert_equal(doc.key(graphs, 1), "primitive")
    assert_equal(doc.key(graphs, 2), "shared")
    assert_equal(
        doc.text(
            doc.item(doc.at(doc.at(doc.root, "closure"), "reference_names"), 0)
        ),
        "curve_bounds.mojo",
    )


def main() raises:
    """Run the input-plan and graph-pin tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
