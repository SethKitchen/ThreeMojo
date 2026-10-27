# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The extra coverage-invariant inputs stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_invariant_gate import invariant_protected_tail


def test_six_protected_inputs_stay_in_order() raises:
    """The grouped contract stays first and the lane-control test stays last."""
    var doc = PyJson.parse(invariant_protected_tail())
    assert_equal(doc.length(doc.root), 6)
    assert_equal(
        doc.text(doc.item(doc.root, 0)),
        "tools/carla_lane_oracle/grouped-table-contract.json",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 1)),
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 2)), "extensions/carla/geometry.mojo"
    )
    assert_equal(
        doc.text(doc.item(doc.root, 5)),
        "tests/test_carla_lane_control_successor.mojo",
    )


def main() raises:
    """Run the coverage-invariant protected-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
