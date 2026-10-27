# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The render-actor module and bound tests stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_render_actor_gate import render_actor_paths


def test_the_module_and_three_tests_stay_in_order() raises:
    """One module comes first, then the three bound tests."""
    var doc = PyJson.parse(render_actor_paths())
    var modules = doc.at(doc.root, "modules")
    var tests = doc.at(doc.root, "tests")
    assert_equal(doc.length(modules), 1)
    assert_equal(
        doc.text(doc.item(modules, 0)), "extensions/carla/render_actors.mojo"
    )
    assert_equal(doc.length(tests), 3)
    assert_equal(
        doc.text(doc.item(tests, 0)), "tests/test_carla_render_reuse.mojo"
    )
    assert_equal(
        doc.text(doc.item(tests, 1)), "tests/test_carla_model_cache.mojo"
    )
    assert_equal(
        doc.text(doc.item(tests, 2)),
        "tests/test_carla_walker_render_motion.mojo",
    )


def main() raises:
    """Run the render-actor path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
