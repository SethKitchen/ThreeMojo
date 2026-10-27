# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The coverage-invariant sources stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_invariant_gate import invariant_sources


def test_four_sources_stay_in_reviewed_order() raises:
    """Support, dispatch, the grouped proof, and lane refinement stay in order.
    """
    var doc = PyJson.parse(invariant_sources())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(
        doc.text(doc.item(doc.root, 0)),
        "extensions/carla/curve_minimizer_support.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 1)),
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 2)),
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 3)), "extensions/carla/lane_refinement.mojo"
    )


def main() raises:
    """Run the coverage-invariant source tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
