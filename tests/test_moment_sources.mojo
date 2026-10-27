# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The moment proof and interval sources stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_moment_gate import moment_sources


def test_the_moment_paths_and_tokens_stay_reviewed() raises:
    """The moment proof stays with the interval module and both tokens."""
    var doc = PyJson.parse(moment_sources())
    assert_equal(
        doc.text(doc.at(doc.root, "module")),
        "extensions/carla/spiral_moment_proof.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "interval")),
        "extensions/carla/curve_interval.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "module_token")),
        "9001f34d01c28de8dcf85af0bec9d9b9409ef8d56e083bfc25d6342c375f80d1",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "interval_token")),
        "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11",
    )


def main() raises:
    """Run the moment source tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
