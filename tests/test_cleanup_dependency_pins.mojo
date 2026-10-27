# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed trig and geometry dependency pins stay in order."""

from std.testing import TestSuite, assert_equal

from tools._cleanup_dependency_pins import cleanup_dependency_pins
from tools._python_json import PyJson


def test_trig_and_geometry_pins_stay_in_order() raises:
    """Trig comes before geometry, and each path keeps its token digest."""
    var doc = PyJson.parse(cleanup_dependency_pins())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(doc.key(doc.root, 0), "trig_path")
    assert_equal(doc.key(doc.root, 1), "trig_token")
    assert_equal(doc.key(doc.root, 2), "geometry_path")
    assert_equal(doc.key(doc.root, 3), "geometry_token")
    assert_equal(
        doc.text(doc.at(doc.root, "trig_path")),
        "extensions/carla/curve_trig.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "trig_token")),
        "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "geometry_path")),
        "extensions/carla/geometry.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "geometry_token")),
        "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb",
    )


def main() raises:
    """Run the cleanup dependency pin tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
