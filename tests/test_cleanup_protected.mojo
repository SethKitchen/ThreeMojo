# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The extra reviewed-cleanup inputs stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_cleanup_gate import cleanup_protected_tail


def test_fourteen_inputs_stay_in_order() raises:
    """The followup record stays first and the roundoff proof stays last."""
    var doc = PyJson.parse(cleanup_protected_tail())
    assert_equal(doc.length(doc.root), 14)
    assert_equal(
        doc.text(doc.item(doc.root, 0)),
        "tools/carla_lane_oracle/coverage-followup-migration.json",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 6)),
        "extensions/carla/spiral_moment_proof.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 13)),
        "extensions/carla/spiral_roundoff_proof.mojo",
    )


def main() raises:
    """Run the cleanup protected-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
