# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The runtime-boundary modules stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_runtime_boundary_gate import runtime_boundary_modules


def test_four_modules_stay_in_reviewed_order() raises:
    """Cameras, lane invasion, the sensor manager, and the world stay in order.
    """
    var doc = PyJson.parse(runtime_boundary_modules())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(
        doc.text(doc.item(doc.root, 0)), "extensions/carla/cameras.mojo"
    )
    assert_equal(
        doc.text(doc.item(doc.root, 1)), "extensions/carla/lane_invasion.mojo"
    )
    assert_equal(
        doc.text(doc.item(doc.root, 2)), "extensions/carla/sensor_manager.mojo"
    )
    assert_equal(doc.text(doc.item(doc.root, 3)), "extensions/carla/world.mojo")


def main() raises:
    """Run the runtime-boundary module tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
