# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The ideal projection digests stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_ideal_gate import ideal_digests


def test_the_legacy_and_projected_digests_stay_reviewed() raises:
    """The historical source digest stays with the projected graph digest."""
    var doc = PyJson.parse(ideal_digests())
    assert_equal(
        doc.text(doc.at(doc.root, "legacy")),
        "270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "projected")),
        "f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06",
    )


def main() raises:
    """Run the ideal digest tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
