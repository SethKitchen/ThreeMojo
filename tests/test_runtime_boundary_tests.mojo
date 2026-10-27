# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The runtime-boundary tests and fixtures stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_runtime_boundary_gate import runtime_boundary_tests


def test_twelve_tests_keep_nine_compile_fail_fixtures() raises:
    """Three sensor tests come first, then nine compile-fail fixtures."""
    var doc = PyJson.parse(runtime_boundary_tests())
    var tests = doc.at(doc.root, "tests")
    var fixtures = doc.at(doc.root, "fixtures")
    assert_equal(doc.length(tests), 12)
    assert_equal(doc.length(fixtures), 9)
    assert_equal(doc.text(doc.item(tests, 0)), "tests/test_carla_sensors.mojo")
    assert_equal(
        doc.text(doc.item(tests, 2)), "tests/test_carla_world_signals.mojo"
    )
    assert_equal(
        doc.text(doc.item(tests, 3)),
        "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo",
    )
    assert_equal(
        doc.text(doc.item(fixtures, 0)),
        "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo",
    )
    assert_equal(
        doc.text(doc.item(tests, 11)),
        "tests/compile_fail/carla_light_search_distance_rejects_raw_float64.mojo",
    )
    assert_equal(doc.text(doc.item(fixtures, 8)), doc.text(doc.item(tests, 11)))


def main() raises:
    """Run the runtime-boundary test-path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
