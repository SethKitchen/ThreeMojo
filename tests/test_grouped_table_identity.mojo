# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The grouped proof module and token digest stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_grouped_gate import grouped_table_identity


def test_the_module_and_token_stay_reviewed() raises:
    """The grouped proof module keeps its reviewed token digest."""
    var doc = PyJson.parse(grouped_table_identity())
    assert_equal(
        doc.text(doc.at(doc.root, "module")),
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "token")),
        "3fcfc637a40c4e322b5747f27f8d77163c3f47a49d1092b37c20744cafecba40",
    )


def main() raises:
    """Run the grouped-table identity tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
