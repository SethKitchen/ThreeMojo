# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The selection producer digests stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_selection_gate import selection_producers


def test_the_grouped_proof_precedes_the_roundoff_proof() raises:
    """The grouped proof stays first and both digests stay reviewed."""
    var doc = PyJson.parse(selection_producers())
    assert_equal(doc.length(doc.root), 2)
    assert_equal(
        doc.key(doc.root, 0),
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    assert_equal(
        doc.text(doc.value(doc.root, 0)),
        "a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7",
    )
    assert_equal(
        doc.key(doc.root, 1), "extensions/carla/spiral_roundoff_proof.mojo"
    )
    assert_equal(
        doc.text(doc.value(doc.root, 1)),
        "634c4f0f448b472301a42ad6065655f60cf78121f12bafa64085a1e67108fc0f",
    )


def main() raises:
    """Run the selection producer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
